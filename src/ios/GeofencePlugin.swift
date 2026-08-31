//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//

import Foundation
import WebKit
import UserNotifications
import CoreLocation

let TAG = "GeofencePlugin"

func log(_ message: String){
    NSLog("%@ - %@", TAG, message)
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

func parseGeofenceDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    private static let pendingTransitionsKey = "PAPAGeofencePendingTransitions"
    private static let maxPendingTransitions = 100

    var geoNotificationManager: GeoNotificationManager!
    let priority = DispatchQoS.QoSClass.default
    private var deviceIsReady = false
    
    override func pluginInitialize () {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveLocalNotification(_:)),
            name: NSNotification.Name(rawValue: "CDVLocalNotification"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveTransition(_:)),
            name: NSNotification.Name(rawValue: "handleTransition"),
            object: nil
        )
        let initializeManager = {
            self.geoNotificationManager = GeoNotificationManager()
            self.geoNotificationManager.restoreMonitoring()
        }
        if Thread.isMainThread {
            initializeManager()
        } else {
            DispatchQueue.main.sync(execute: initializeManager)
        }
    }
    
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        log("Plugin initialization")
        // let faker = GeofenceFaker(manager: geoNotificationManager)
        // faker.start()
        
        promptForNotificationPermission()
		// comment to remove permissions
         geoNotificationManager.registerPermissions()

        let (ok, warnings, errors) = geoNotificationManager.checkRequirements()
        
        log(warnings)
        log(errors)
        
        let result: CDVPluginResult
        
        if ok {
            result = CDVPluginResult(status: CDVCommandStatus.ok, messageAs: warnings.joined(separator: "\n"))
        } else {
            result = CDVPluginResult(
                status: CDVCommandStatus.illegalAccessException,
                messageAs: (errors + warnings).joined(separator: "\n")
            )
        }
        
        commandDelegate!.send(result, callbackId: command.callbackId)
    }
    
    @objc func deviceReady(_ command: CDVInvokedUrlCommand) {
        deviceIsReady = true
        flushPendingTransitions()
        let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc func ping(_ command: CDVInvokedUrlCommand) {
        log("Ping")
        let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
        commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc func promptForNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert, .badge]) { granted, error in
            if let error = error {
                log("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func addOrUpdate(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            let geoNotifications = command.arguments.map { JSON($0) }
            if let error = self.geoNotificationManager.addOrUpdateGeoNotifications(geoNotifications) {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.error, messageAs: error)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            } else {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }

    @objc func replace(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            guard command.arguments.count == 2,
                let rawIds = command.arguments[0] as? [Any],
                let rawGeoNotifications = command.arguments[1] as? [Any] else {
                let error: [String: Any] = [
                    "code": "INVALID_ARGUMENTS",
                    "message": "replace requires an ID array and a geofence array."
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.error, messageAs: error)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            let ids = rawIds.compactMap { $0 as? String }
            let geoNotifications = rawGeoNotifications.map { JSON($0) }
            if let error = self.geoNotificationManager.replaceGeoNotifications(
                removing: ids,
                with: geoNotifications
            ) {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.error, messageAs: error)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            } else {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func getWatched(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.global(qos: priority).async {
            let watched = self.geoNotificationManager.getWatchedGeoNotifications()!
            let watchedJsonString = watched.description
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok, messageAs: watchedJsonString)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func remove(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            for id in command.arguments {
                self.geoNotificationManager.removeGeoNotification(id as! String)
            }
            let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc func removeAll(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            self.geoNotificationManager.removeAllGeoNotifications()
            let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc func snooze(_ command: CDVInvokedUrlCommand) {
        log("snooze")
        DispatchQueue.main.async {
            if command.arguments.count == 2,
                let duration = command.arguments[1] as? NSNumber {
                let id = String(describing: command.arguments[0])
                self.geoNotificationManager.snoozeFence(id, duration: duration.doubleValue)
            }
            let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        }
    }
    
    @objc func dismissNotifications(_ command: CDVInvokedUrlCommand) {
        log("dismissNotifications")
        DispatchQueue.global(qos: priority).async {
            if let ids = command.arguments as? [Int] {
                self.geoNotificationManager.dismissNotifications(ids.map { String($0) })
            }
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus.ok)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        }
    }
    
    @objc func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {
            if deviceIsReady && webView != nil {
                deliverTransition(geoNotificationString)
            } else {
                persistPendingTransition(geoNotificationString)
            }
        }
    }

    private func deliverTransition(_ geoNotificationString: String) {
        let escaped = geoNotificationString.replacingOccurrences(of: "'", with: "\\'")
        let js = "setTimeout('geofence.onTransitionReceived([" + escaped + "])',0)"
        evaluateJs(js)
    }

    private func persistPendingTransition(_ geoNotificationString: String) {
        var transitions = UserDefaults.standard.stringArray(forKey: Self.pendingTransitionsKey) ?? []
        transitions.append(geoNotificationString)
        if transitions.count > Self.maxPendingTransitions {
            transitions.removeFirst(transitions.count - Self.maxPendingTransitions)
        }
        UserDefaults.standard.set(transitions, forKey: Self.pendingTransitionsKey)
    }

    private func flushPendingTransitions() {
        let defaults = UserDefaults.standard
        let transitions = defaults.stringArray(forKey: Self.pendingTransitionsKey) ?? []
        defaults.removeObject(forKey: Self.pendingTransitionsKey)
        transitions.forEach(deliverTransition)
    }
    
    @objc func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        var data = "undefined"
        if let geoNotificationString = notification.object as? String {
            data = geoNotificationString
        }
        
        let js = "setTimeout('geofence.onNotificationClicked(" + data.replacingOccurrences(of: "'", with: "\\'") + ")',0)"
        
        evaluateJs(js)
    }
    
    func evaluateJs (_ script: String) {
        if let webView = webView {
            // if let uiWebView = webView as? UIWebView {
            //    uiWebView.stringByEvaluatingJavaScript(from: script)
            //} else if let wkWebView = webView as? WKWebView {
            if let wkWebView = webView as? WKWebView {
                wkWebView.evaluateJavaScript(script, completionHandler: nil)
            }
        } else {
            log("webView is nil")
        }
    }
    
    override func onAppTerminate() {
        log("onAppTerminate")
        deviceIsReady = false
        super.onAppTerminate()
    }
}

// class for faking crossing geofences
class GeofenceFaker {
    let priority = DispatchQoS.QoSClass.default
    let geoNotificationManager: GeoNotificationManager
    
    init(manager: GeoNotificationManager) {
        geoNotificationManager = manager
    }
    
    func start() {
        DispatchQueue.global(qos: priority).async {
            while (true) {
                log("FAKER")
                let notify = arc4random_uniform(4)
                if notify == 0 {
                    log("FAKER notify chosen, need to pick up some region")
                    var geos = self.geoNotificationManager.getWatchedGeoNotifications()!
                    if geos.count > 0 {
                        //WTF Swift??
                        let index = arc4random_uniform(UInt32(geos.count))
                        let geo = geos[Int(index)]
                        let id = geo["id"].stringValue
                        DispatchQueue.main.async {
                            if let region = self.geoNotificationManager.getMonitoredRegion(id) {
                                log("FAKER Trigger didEnterRegion")
                                self.geoNotificationManager.locationManager(
                                    self.geoNotificationManager.locationManager,
                                    didEnterRegion: region
                                )
                            }
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }
    
    func stop() {
        
    }
}

class GeoNotificationManager : NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let maximumMonitoredRegions = 20

    let locationManager = CLLocationManager()
    let store = GeoNotificationStore()
    var snoozedFences = [String : Double]()
    var snoozeWorkItems = [String : DispatchWorkItem]()
    lazy var trackingCoordinator = GeofenceTrackingCoordinator(
        store: store,
        isSnoozed: { [weak self] id in self?.isSnoozed(id) ?? false }
    )
    
    override init() {
        log("GeoNotificationManager init")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        UNUserNotificationCenter.current().delegate = self
    }
    
    func registerPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    func addOrUpdateGeoNotifications(_ geoNotifications: [JSON]) -> [String: Any]? {
        return replaceGeoNotifications(removing: [], with: geoNotifications)
    }

    func replaceGeoNotifications(removing ids: [String], with geoNotifications: [JSON]) -> [String: Any]? {
        let existing = store.getAll() ?? []
        let existingIds = Set(existing.map { $0["id"].stringValue })
        let removedIds = Set(ids)
        var prospectiveIds = existingIds.subtracting(removedIds)
        geoNotifications.forEach { prospectiveIds.insert($0["id"].stringValue) }

        let externalRegionCount = locationManager.monitoredRegions.filter {
            !existingIds.contains($0.identifier)
        }.count
        if prospectiveIds.count + externalRegionCount > Self.maximumMonitoredRegions {
            return [
                "code": "GEOFENCE_LIMIT_EXCEEDED",
                "message": "iOS can monitor at most 20 regions at the same time."
            ]
        }

        let incomingIds = Set(geoNotifications.map { $0["id"].stringValue })
        for id in removedIds.intersection(existingIds) where !incomingIds.contains(id) {
            removeGeoNotificationWithoutReconcile(id)
        }
        geoNotifications.forEach(addOrUpdateGeoNotification)
        trackingCoordinator.reconcile()
        return nil
    }

    private func addOrUpdateGeoNotification(_ geoNotification: JSON) {
        var geoNotification = geoNotification
        log("GeoNotificationManager addOrUpdate")
        
        let (_, warnings, errors) = checkRequirements()
        
        log(warnings)
        log(errors)
        
        let location = CLLocationCoordinate2DMake(
            geoNotification["latitude"].doubleValue,
            geoNotification["longitude"].doubleValue
        )
        log("AddOrUpdate geo: \(geoNotification)")
        let radius = geoNotification["radius"].doubleValue as CLLocationDistance
        let id = geoNotification["id"].stringValue
        
        let region = CLCircularRegion(center: location, radius: radius, identifier: id)
        
        var transitionType = 0
        if let i = geoNotification["transitionType"].int {
            transitionType = i
        }
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2

        if let existing = store.findById(id) {
            geoNotification["isInside"] = existing["isInside"]
            geoNotification["lastTransitionType"] = existing["lastTransitionType"]
            geoNotification["lastTransitionDelivered"] = existing["lastTransitionDelivered"]
            geoNotification["stateKnown"] = existing["stateKnown"].isExists() ?
                existing["stateKnown"] : JSON(existing["lastTransitionType"].intValue != 0)
        } else {
            geoNotification["isInside"] = false
            geoNotification["lastTransitionType"] = 0
            geoNotification["lastTransitionDelivered"] = false
            geoNotification["stateKnown"] = false
        }
        //store
        store.addOrUpdate(geoNotification)
        locationManager.startMonitoring(for: region)
    }

    func restoreMonitoring() {
        let monitoredIds = Set(locationManager.monitoredRegions.map { $0.identifier })
        for var geoNotification in store.getAll() ?? [] {
            let id = geoNotification["id"].stringValue
            if let region = getMonitoredRegion(id) {
                locationManager.requestState(for: region)
                continue
            }

            if !monitoredIds.contains(id) {
                geoNotification["lastTransitionDelivered"] = false
                geoNotification["stateKnown"] = false
                store.addOrUpdate(geoNotification)
                locationManager.startMonitoring(for: makeRegion(geoNotification))
            }
        }
        trackingCoordinator.reconcile()
    }

    private func makeRegion(_ geoNotification: JSON) -> CLCircularRegion {
        let center = CLLocationCoordinate2DMake(
            geoNotification["latitude"].doubleValue,
            geoNotification["longitude"].doubleValue
        )
        let region = CLCircularRegion(
            center: center,
            radius: geoNotification["radius"].doubleValue,
            identifier: geoNotification["id"].stringValue
        )
        let transitionType = geoNotification["transitionType"].intValue
        region.notifyOnEntry = 0 != transitionType & 1
        region.notifyOnExit = 0 != transitionType & 2
        return region
    }
    
    func checkRequirements() -> (Bool, [String], [String]) {
        var errors = [String]()
        var warnings = [String]()
        
        if (!CLLocationManager.isMonitoringAvailable(for: CLRegion.self)) {
            errors.append("Geofencing not available")
        }
        
        if (!CLLocationManager.locationServicesEnabled()) {
            errors.append("Error: Locationservices not enabled")
        }
        
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }

        if authStatus != .authorizedAlways {
            if authStatus != .authorizedWhenInUse {
                errors.append("Error: Location when in use permissions not granted")
            } else {
                warnings.append("Warning: Location always permissions not granted")
            }
        }
        
        // Notification permissions are managed asynchronously through UNUserNotificationCenter.
        let ok = (errors.count == 0)
        return (ok, warnings, errors)
    }
    
    func getWatchedGeoNotifications() -> [JSON]? {
        return store.getAll()
    }
    
    func getMonitoredRegion(_ id: String) -> CLRegion? {
        for object in locationManager.monitoredRegions {
            let region = object
            
            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }
    
    func removeGeoNotification(_ id: String) {
        removeGeoNotificationWithoutReconcile(id)
        trackingCoordinator.handleTransition(2)
    }

    private func removeGeoNotificationWithoutReconcile(_ id: String) {
        guard store.findById(id) != nil else {
            return
        }
        store.remove(id)
        let region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            locationManager.stopMonitoring(for: region!)
        }
        snoozedFences.removeValue(forKey: id)
        snoozeWorkItems[id]?.cancel()
        snoozeWorkItems.removeValue(forKey: id)
    }
    
    func removeAllGeoNotifications() {
        let ownedIds = Set((store.getAll() ?? []).map { $0["id"].stringValue })
        store.clear()
        for object in locationManager.monitoredRegions where ownedIds.contains(object.identifier) {
            let region = object
            log("Stoping monitoring region \(region.identifier)")
            locationManager.stopMonitoring(for: region)
        }
        snoozeWorkItems.values.forEach { $0.cancel() }
        snoozeWorkItems.removeAll()
        snoozedFences.removeAll()
        trackingCoordinator.handleTransition(2)
    }
    
    func handleTransition(_ id: String, transitionType: Int) {
        updatePhysicalState(id, transitionType: transitionType, deliverEvent: true)
    }

    private func updatePhysicalState(_ id: String, transitionType: Int, deliverEvent: Bool) {
        guard var storedNotification = store.findById(id) else {
            return
        }

        let isInside = transitionType == 1 || transitionType == 4
        let previousTransition = storedNotification["lastTransitionType"].intValue
        let previousInside = storedNotification["isInside"].boolValue
        let previousStateKnown = storedNotification["stateKnown"].boolValue
        let configuredTransitionType = storedNotification["transitionType"].intValue
        let transitionMask = isInside ? 1 : 2
        let shouldDeliver = deliverEvent &&
            configuredTransitionType & transitionMask != 0 &&
            !isSnoozed(id) &&
            isWithinTimeRange(storedNotification)

        if previousStateKnown && previousTransition == transitionType && previousInside == isInside {
            trackingCoordinator.handleTransition(transitionType)
            if shouldDeliver && !storedNotification["lastTransitionDelivered"].boolValue {
                storedNotification["lastTransitionDelivered"] = true
                store.addOrUpdate(storedNotification)
                var eventNotification = storedNotification
                eventNotification["transitionType"] = JSON(transitionType)
                deliverTransition(eventNotification)
            }
            return
        }

        storedNotification["isInside"] = JSON(isInside)
        storedNotification["lastTransitionType"] = JSON(transitionType)
        storedNotification["lastTransitionDelivered"] = JSON(shouldDeliver)
        storedNotification["stateKnown"] = true
        store.addOrUpdate(storedNotification)
        trackingCoordinator.handleTransition(transitionType)

        guard shouldDeliver else {
            return
        }

        var eventNotification = storedNotification
        eventNotification["transitionType"] = JSON(transitionType)
        deliverTransition(eventNotification)
    }

    private func deliverTransition(_ geoNotification: JSON) {
        if geoNotification["notification"].isExists() && canBeTriggered(geoNotification) {
            notifyAbout(geoNotification)
        }

        if geoNotification["url"].isExists(),
            let url = URL(string: geoNotification["url"].stringValue) {
            log("Should post to " + geoNotification["url"].stringValue)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            let jsonDict = [
                "geofenceId": geoNotification["id"].stringValue,
                "transition": geoNotification["transitionType"].intValue == 1 ? "ENTER" : "EXIT",
                "date": dateFormatter.string(from: Date())
            ]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: []) else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "post"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(geoNotification["authorization"].stringValue, forHTTPHeaderField: "Authorization")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    print("error:", error)
                    return
                }
                guard let data = data else { return }
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    print("json:", json)
                } catch {
                    print("error:", error)
                }
            }.resume()
        }

        NotificationCenter.default.post(
            name: Notification.Name(rawValue: "handleTransition"),
            object: geoNotification.rawString(String.Encoding.utf8.rawValue, options: [])
        )
    }
    
    func canBeTriggered(_ geo: JSON) -> Bool {
        let store = GeoNotificationStore()
        if(geo["notification"]["lastTriggered"].isExists() && geo["notification"]["frequency"].isExists()) {
            if(Int(NSDate().timeIntervalSince1970) < geo["notification"]["lastTriggered"].int! + geo["notification"]["frequency"].int!) {
                log("Frequency control. Skip notification")
                return false
            }
        }
        store.updateLastTriggeredByNotificationId(geo["notification"]["id"].stringValue)
        return true
    }
    
    func isWithinTimeRange(_ geoNotification: JSON) -> Bool {
        let now = Date()
        var greaterThanOrEqualToStartTime: Bool = true
        var lessThanEndTime: Bool = true
        if geoNotification["startTime"].isExists() {
            if let startTime = parseDate(dateStr: geoNotification["startTime"].stringValue) {
                greaterThanOrEqualToStartTime = (now.compare(startTime) == ComparisonResult.orderedDescending || now.compare(startTime) == ComparisonResult.orderedSame)
            }
        }
        if geoNotification["endTime"].isExists() {
            if let endTime = parseDate(dateStr: geoNotification["endTime"].stringValue) {
                lessThanEndTime = now.compare(endTime) == ComparisonResult.orderedAscending
            }
        }
        return greaterThanOrEqualToStartTime && lessThanEndTime
    }
    
    func parseDate(dateStr: String?) -> Date? {
        guard let dateStr = dateStr else {
            return nil
        }
        return parseGeofenceDate(dateStr)
    }
    
    func notifyAbout(_ geo: JSON) {
        log("Creating notification")
        let content = UNMutableNotificationContent()
        if let title = geo["notification"]["title"] as JSON? {
            content.title = title.stringValue
        }
        if let text = geo["notification"]["text"] as JSON? {
            content.body = text.stringValue
        }
        content.sound = UNNotificationSound.default
        if let json = geo["notification"]["data"] as JSON? {
            content.userInfo = ["geofence.notification.data": json.rawString(String.Encoding.utf8.rawValue, options: [])!]
        }
        let identifier = geo["notification"]["id"].stringValue
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: { (error) in
            if error != nil {
                log("Couldn't create notification")
            }
        })
    }
    
    func dismissNotifications(_ ids: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
    
    func snoozeFence(_ id: String, duration: Double) {
        snoozeWorkItems[id]?.cancel()
        snoozeWorkItems.removeValue(forKey: id)

        if duration <= 0 {
            snoozedFences.removeValue(forKey: id)
        } else {
            snoozedFences[id] = NSTimeIntervalSince1970 + duration
            let workItem = DispatchWorkItem { [weak self] in
                self?.snoozedFences.removeValue(forKey: id)
                self?.snoozeWorkItems.removeValue(forKey: id)
                self?.trackingCoordinator.reconcile()
            }
            snoozeWorkItems[id] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
        trackingCoordinator.reconcile()
    }
    
    func isSnoozed(_ id: String?) -> Bool {
        guard let id = id, let fenceTime = snoozedFences[id] else {
            return false
        }
        return fenceTime > NSTimeIntervalSince1970
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("fail with error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log("deferred fail error: \(String(describing: error))")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        updatePhysicalState(region.identifier, transitionType: 1, deliverEvent: true)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        updatePhysicalState(region.identifier, transitionType: 2, deliverEvent: true)
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if region is CLCircularRegion {
            let lat = (region as! CLCircularRegion).center.latitude
            let lng = (region as! CLCircularRegion).center.longitude
            let radius = (region as! CLCircularRegion).radius
            
            log("Starting monitoring for region \(region) lat \(lat) lng \(lng) of radius \(radius)")
        }
        locationManager.requestState(for: region)
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        log("State for region " + region.identifier)
        if state == .inside {
            updatePhysicalState(region.identifier, transitionType: 1, deliverEvent: false)
        } else if state == .outside {
            updatePhysicalState(region.identifier, transitionType: 2, deliverEvent: false)
        } else {
            trackingCoordinator.reconcile()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log("Monitoring region " + (region?.identifier ?? "unknown") + " failed \(error)" )
    }
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.userInfo["geofence.notification.data"] != nil {
            // Play sound and show alert to the user if it is a geofence notification
            if #available(iOS 14.0, *) {
                completionHandler([.banner, .sound])
            } else {
                completionHandler([.alert, .sound])
            }
        } else if (notification.request.content.userInfo["foreground"] != nil) {
            // Play sound and show alert to the user if the notification has foreground property
            if #available(iOS 14.0, *) {
                completionHandler([.banner, .sound])
            } else {
                completionHandler([.alert, .sound])
            }
        } else {
            completionHandler([])
        }
    }
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Determine the user action
        log(response.actionIdentifier)
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            log("Dismiss Action")
        case UNNotificationDefaultActionIdentifier:
            if let data = response.notification.request.content.userInfo["geofence.notification.data"] {
                log("userNotificationCenter didReceive: \(data)")
                NotificationCenter.default.post(name: Notification.Name(rawValue: "CDVLocalNotification"), object: data)
            }
        case "Snooze":
            snoozeFence(response.notification.request.identifier, duration: 86400)
        case "Delete":
            snoozeFence(response.notification.request.identifier, duration: 300)
        default:
            log("Unknown action")
        }
        completionHandler()
    }
}

class GeoNotificationStore {
    init() {
        createDBStructure()
    }
    
    func createDBStructure() {
        let (tables, err) = SD.existingTables()
        
        if (err != nil) {
            log("Cannot fetch sqlite tables: \(String(describing: err))")
            return
        }
        
        if (tables.filter { $0 == "GeoNotifications" }.count == 0) {
            if let err = SD.executeChange("CREATE TABLE GeoNotifications (ID TEXT PRIMARY KEY, Data TEXT)") {
                //there was an error during this function, handle it here
                log("Error while creating GeoNotifications table: \(err)")
            } else {
                //no error, the table was created successfully
                log("GeoNotifications table was created successfully")
            }
        }
    }
    
    func addOrUpdate(_ geoNotification: JSON) {
        NSLog("geoNotification.description: %@", geoNotification.description)
        if (findById(geoNotification["id"].stringValue) != nil) {
            update(geoNotification)
        }
        else {
            add(geoNotification)
        }
    }
    
    func add(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        var notificationCopy = geoNotification
        notificationCopy["lastTriggered"] = 0
        let err = SD.executeChange("INSERT INTO GeoNotifications (Id, Data) VALUES(?, ?)",
                                   withArgs: [id as AnyObject, notificationCopy.description as AnyObject])
        
        if err != nil {
            log("Error while adding \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func update(_ geoNotification: JSON) {
        let id = geoNotification["id"].stringValue
        let err = SD.executeChange("UPDATE GeoNotifications SET Data = ? WHERE Id = ?",
                                   withArgs: [geoNotification.description as AnyObject, id as AnyObject])
        
        if err != nil {
            log("Error while adding \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func updateLastTriggeredByNotificationId(_ id: String) {
        if let allStored = getAll() {
            for var json in allStored {
                if json["notification"]["id"].stringValue == id {
                    json["notification"]["lastTriggered"] = JSON(NSDate().timeIntervalSince1970)
                    update(json)
                }
            }
        }
    }

    func findById(_ id: String) -> JSON? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching \(id) GeoNotification table: \(String(describing: err))")
            return nil
        } else {
            if (resultSet.count > 0) {
                let jsonString = resultSet[0]["Data"]!.asString()!
                return JSON(data: jsonString.data(using: String.Encoding.utf8)!)
            }
            else {
                return nil
            }
        }
    }
    
    func getAll() -> [JSON]? {
        let (resultSet, err) = SD.executeQuery("SELECT * FROM GeoNotifications")
        
        if err != nil {
            //there was an error during the query, handle it here
            log("Error while fetching from GeoNotifications table: \(String(describing: err))")
            return nil
        } else {
            var results = [JSON]()
            for row in resultSet {
                if let data = row["Data"]?.asString() {
                    results.append(JSON(data: data.data(using: String.Encoding.utf8)!))
                }
            }
            return results
        }
    }
    
    func remove(_ id: String) {
        let err = SD.executeChange("DELETE FROM GeoNotifications WHERE Id = ?", withArgs: [id as AnyObject])
        
        if err != nil {
            log("Error while removing \(id) GeoNotification: \(String(describing: err))")
        }
    }
    
    func clear() {
        let err = SD.executeChange("DELETE FROM GeoNotifications")
        
        if err != nil {
            log("Error while deleting all from GeoNotifications: \(String(describing: err))")
        }
    }
}
