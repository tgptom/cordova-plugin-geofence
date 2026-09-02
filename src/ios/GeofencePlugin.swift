//
//  GeofencePlugin.swift
//  ionic-geofence
//
//  Created by tomasz on 07/10/14.
//
//

import Foundation
import UIKit
import WebKit
import UserNotifications
import CoreLocation

let TAG = "GeofencePlugin"
let AppGeofenceTrackingTransition = "AppGeofenceTrackingTransition"
let GeofenceTrackingTransitionTypeKey = "transitionType"
let GeofenceTrackingHasActiveInsideKey = "hasActiveInsideGeofence"
let GeofenceMonitoringErrorNotification = "handleMonitoringError"
let GeofenceTransitionEnter = 1
let GeofenceTransitionExit = 2
let GeofenceTransitionDwell = 4

func log(_ message: String){
    NSLog("%@ - %@", TAG, message)
}

func log(_ messages: [String]) {
    for message in messages {
        log(message);
    }
}

@objc(HWPGeofencePlugin) class GeofencePlugin : CDVPlugin {
    lazy var geoNotificationManager = GeoNotificationManager()
    
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(GeofencePlugin.didReceiveMonitoringError(_:)),
            name: NSNotification.Name(rawValue: GeofenceMonitoringErrorNotification),
            object: nil
        )
        geoNotificationManager = GeoNotificationManager()
        geoNotificationManager.performSerialized {
            self.geoNotificationManager.reconcileMonitoredGeofencesAndState()
        }
    }
    
    @objc func initialize(_ command: CDVInvokedUrlCommand) {
        log("Plugin initialization")
        // let faker = GeofenceFaker(manager: geoNotificationManager)
        // faker.start()
        
        promptForNotificationPermission()
        runSerializedCommand(command) {
            self.geoNotificationManager.registerPermissions()
            self.geoNotificationManager.isActive = true
            self.geoNotificationManager.reconcileMonitoredGeofencesAndState()
            
            let (ok, warnings, errors) = self.geoNotificationManager.checkRequirements()
            
            log(warnings)
            log(errors)
            
            if ok {
                return CDVPluginResult(status: CDVCommandStatus.ok, messageAs: warnings.joined(separator: "\n"))
            }
            return CDVPluginResult(
                status: CDVCommandStatus.illegalAccessException,
                messageAs: (errors + warnings).joined(separator: "\n")
            )
        }
    }
    
    @objc func deviceReady(_ command: CDVInvokedUrlCommand) {
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
        runSerializedCommand(command) {
            try self.geoNotificationManager.addOrUpdateGeoNotifications(command.arguments.map { JSON($0) })
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func getWatched(_ command: CDVInvokedUrlCommand) {
        runSerializedCommand(command) {
            let watched = self.geoNotificationManager.getWatchedGeoNotifications() ?? []
            return CDVPluginResult(status: CDVCommandStatus.ok, messageAs: watched.description)
        }
    }

    @objc func replace(_ command: CDVInvokedUrlCommand) {
        runSerializedCommand(command) {
            let payload: [Any]
            if let firstArgument = command.arguments.first as? [Any] {
                payload = firstArgument
            } else {
                payload = command.arguments
            }
            try self.geoNotificationManager.replaceGeoNotifications(payload.map { JSON($0) })
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func remove(_ command: CDVInvokedUrlCommand) {
        runSerializedCommand(command) {
            for id in command.arguments {
                if let stringId = id as? String {
                    self.geoNotificationManager.removeGeoNotification(stringId)
                } else if let numberId = id as? NSNumber {
                    self.geoNotificationManager.removeGeoNotification(numberId.stringValue)
                } else {
                    throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Geofence id must be a string or number"])
                }
            }
            self.geoNotificationManager.reconcileTrackingState()
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func removeAll(_ command: CDVInvokedUrlCommand) {
        runSerializedCommand(command) {
            self.geoNotificationManager.removeAllGeoNotifications()
            self.geoNotificationManager.reconcileTrackingState()
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func snooze(_ command: CDVInvokedUrlCommand) {
        log("snooze")
        runSerializedCommand(command) {
            if command.arguments.count < 2 {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "snooze requires id and duration arguments"])
            }

            let id: String
            if let stringId = command.arguments[0] as? String {
                id = stringId
            } else if let numberId = command.arguments[0] as? NSNumber {
                id = numberId.stringValue
            } else {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "snooze id must be a string or number"])
            }

            if let duration = command.arguments[1] as? NSNumber {
                self.geoNotificationManager.snoozeFence(id, duration: duration.doubleValue)
            } else {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "snooze duration must be numeric"])
            }
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func dismissNotifications(_ command: CDVInvokedUrlCommand) {
        log("dismissNotifications")
        runSerializedCommand(command) {
            if let ids = command.arguments as? [Int] {
                self.geoNotificationManager.dismissNotifications(ids.map { String($0) })
            }
            return CDVPluginResult(status: CDVCommandStatus.ok)
        }
    }
    
    @objc func didReceiveTransition (_ notification: Notification) {
        log("didReceiveTransition")
        if let geoNotificationString = notification.object as? String {
            let payload = "[" + geoNotificationString + "]"
            if let js = buildSafeCallbackJs(functionName: "geofence.onTransitionReceived", jsonPayload: payload) {
                evaluateJs(js)
            }
        }
    }
    
    @objc func didReceiveLocalNotification (_ notification: Notification) {
        log("didReceiveLocalNotification")
        var script = "setTimeout(function(){ geofence.onNotificationClicked(undefined); },0)"
        if let geoNotificationString = notification.object as? String {
            if let js = buildSafeCallbackJs(functionName: "geofence.onNotificationClicked", jsonPayload: geoNotificationString) {
                script = js
            }
        }

        evaluateJs(script)
    }

    @objc func didReceiveMonitoringError (_ notification: Notification) {
        if let errorPayload = notification.object as? String,
           let js = buildSafeCallbackJs(functionName: "geofence.onMonitoringError", jsonPayload: errorPayload) {
            evaluateJs(js)
        }
    }

    @objc func didBecomeActive() {
        geoNotificationManager.performSerialized {
            self.geoNotificationManager.reconcileMonitoredGeofencesAndState()
        }
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

    func buildSafeCallbackJs(functionName: String, jsonPayload: String) -> String? {
        guard let payloadData = jsonPayload.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: payloadData, options: [])) != nil else {
            log("Ignoring malformed callback payload for \(functionName)")
            return nil
        }

        guard let quotedPayload = quotedJsonStringLiteral(jsonPayload) else {
            log("Failed to quote callback payload for \(functionName)")
            return nil
        }

        return "setTimeout(function(){ \(functionName)(JSON.parse(\(quotedPayload))); },0)"
    }

    func quotedJsonStringLiteral(_ value: String) -> String? {
        guard let quotedData = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let quotedArray = String(data: quotedData, encoding: .utf8),
              quotedArray.count >= 2 else {
            return nil
        }
        return String(quotedArray.dropFirst().dropLast())
    }
    
    override func onAppTerminate() {
        log("onAppTerminate")
        geoNotificationManager.performSerialized {
            self.geoNotificationManager.isActive = false
        }
        super.onAppTerminate()
    }

    func runSerializedCommand(
        _ command: CDVInvokedUrlCommand,
        work: @escaping () throws -> CDVPluginResult
    ) {
        geoNotificationManager.performSerialized {
            let pluginResult: CDVPluginResult
            do {
                pluginResult = try work()
            } catch {
                pluginResult = CDVPluginResult(status: CDVCommandStatus.error, messageAs: error.localizedDescription)
            }
            DispatchQueue.main.async {
                self.commandDelegate?.send(pluginResult, callbackId: command.callbackId)
            }
        }
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
    let locationManager: CLLocationManager
    let store = GeoNotificationStore()
    let defaults = UserDefaults.standard
    let operationQueue = DispatchQueue(label: "com.cowbell.cordova.geofence.GeoNotificationManagerQueue")
    private(set) var alwaysAuthorizationRequestCount = 0
    var snoozedFences = [String : Double]()
    var isActive = false
    var pendingExitWorkItem: DispatchWorkItem?
    let pendingExitAtKey = "com.cowbell.cordova.geofence.pendingExitAt"
    let lastActiveInsideKey = "com.cowbell.cordova.geofence.lastActiveInside"
    let exitDebounceSeconds: TimeInterval = 30
    let maxMonitoredRegions = 20
    
    override init() {
        var manager: CLLocationManager!
        if Thread.isMainThread {
            manager = CLLocationManager()
        } else {
            DispatchQueue.main.sync {
                manager = CLLocationManager()
            }
        }
        locationManager = manager
        log("GeoNotificationManager init")
        super.init()
        performOnLocationManagerThread {
            self.locationManager.delegate = self
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    func registerPermissions() {
        alwaysAuthorizationRequestCount += 1
        performOnLocationManagerThread {
            self.locationManager.requestAlwaysAuthorization()
        }
    }

    func performSerialized(_ work: @escaping () -> Void) {
        operationQueue.async(execute: work)
    }

    func performOnLocationManagerThread(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
            return
        }
        DispatchQueue.main.sync(execute: work)
    }

    func monitoredRegionsSnapshot() -> [CLRegion] {
        var monitoredRegions: [CLRegion] = []
        performOnLocationManagerThread {
            monitoredRegions = Array(self.locationManager.monitoredRegions)
        }
        return monitoredRegions
    }

    func addOrUpdateGeoNotifications(_ geoNotifications: [JSON]) throws {
        let watched = store.getAll() ?? []
        var existingIds = Set(watched.map { $0["id"].stringValue })
        let incomingIds = try validateIncomingGeofences(geoNotifications)
        let newIds = incomingIds.subtracting(existingIds)
        if existingIds.count + newIds.count > maxMonitoredRegions {
            throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "iOS can monitor at most \(maxMonitoredRegions) geofences"])
        }

        for geo in geoNotifications {
            addOrUpdateGeoNotification(geo)
            existingIds.insert(geo["id"].stringValue)
        }

        reconcileTrackingState()
    }

    func replaceGeoNotifications(_ geoNotifications: [JSON]) throws {
        let previousGeofences = store.getAll() ?? []
        let incomingIds = try validateIncomingGeofences(geoNotifications)
        if incomingIds.count > maxMonitoredRegions {
            throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "iOS can monitor at most \(maxMonitoredRegions) geofences"])
        }

        removeAllGeoNotificationsInternal(notifyTransition: false)
        for geo in geoNotifications {
            addOrUpdateGeoNotification(geo)
        }
        reconcileTrackingState()

        let watchedIds = Set((store.getAll() ?? []).map { $0["id"].stringValue })
        if watchedIds != incomingIds {
            removeAllGeoNotificationsInternal(notifyTransition: false)
            for oldGeo in previousGeofences {
                addOrUpdateGeoNotification(oldGeo)
            }
            reconcileTrackingState()
            throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "replace operation failed and has been rolled back"])
        }
    }

    func validateIncomingGeofences(_ geoNotifications: [JSON]) throws -> Set<String> {
        var incomingIds = Set<String>()
        for geo in geoNotifications {
            let id = geo["id"].stringValue
            if id.isEmpty {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Geofence id is required"])
            }
            if incomingIds.contains(id) {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Duplicate geofence id in request: \(id)"])
            }
            incomingIds.insert(id)

            if geo["radius"].doubleValue <= 0 {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Geofence radius must be greater than 0 for id \(id)"])
            }

            let latitude = geo["latitude"].doubleValue
            if latitude < -90 || latitude > 90 {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Geofence latitude must be between -90 and 90 for id \(id)"])
            }

            let longitude = geo["longitude"].doubleValue
            if longitude < -180 || longitude > 180 {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Geofence longitude must be between -180 and 180 for id \(id)"])
            }

            let transitionType = geo["transitionType"].intValue
            if transitionType != GeofenceTransitionEnter &&
                transitionType != GeofenceTransitionExit &&
                transitionType != (GeofenceTransitionEnter | GeofenceTransitionExit) &&
                transitionType != GeofenceTransitionDwell &&
                transitionType != (GeofenceTransitionEnter | GeofenceTransitionDwell) &&
                transitionType != (GeofenceTransitionExit | GeofenceTransitionDwell) &&
                transitionType != (GeofenceTransitionEnter | GeofenceTransitionExit | GeofenceTransitionDwell) {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported transitionType for id \(id)"])
            }

            if geo["startTime"].isExists() && parseDate(dateStr: geo["startTime"].stringValue) == nil {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid startTime for id \(id)"])
            }

            if geo["endTime"].isExists() && parseDate(dateStr: geo["endTime"].stringValue) == nil {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid endTime for id \(id)"])
            }

            if let start = parseDate(dateStr: geo["startTime"].string),
               let end = parseDate(dateStr: geo["endTime"].string),
               start >= end {
                throw NSError(domain: TAG, code: 1, userInfo: [NSLocalizedDescriptionKey: "startTime must be before endTime for id \(id)"])
            }
        }
        return incomingIds
    }

    func addOrUpdateGeoNotification(_ geoNotification: JSON) {
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

        if !geoNotification["isInside"].isExists() {
            let existingInsideState = store.findById(id)?["isInside"].boolValue ?? false
            geoNotification["isInside"] = existingInsideState
        }
        //store
        store.addOrUpdate(geoNotification)
        performOnLocationManagerThread {
            self.locationManager.startMonitoring(for: region)
            self.locationManager.requestState(for: region)
        }
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
        
        let authStatus: CLAuthorizationStatus = {
            var status = CLLocationManager.authorizationStatus()
            performOnLocationManagerThread {
                if #available(iOS 14.0, *) {
                    status = self.locationManager.authorizationStatus
                } else {
                    status = CLLocationManager.authorizationStatus()
                }
            }
            return status
        }()

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
        for object in monitoredRegionsSnapshot() {
            let region = object
            
            if (region.identifier == id) {
                return region
            }
        }
        return nil
    }
    
    func removeGeoNotification(_ id: String) {
        let wasInside = store.findById(id)?["isInside"].boolValue ?? false
        store.remove(id)
        let region = getMonitoredRegion(id)
        if (region != nil) {
            log("Stoping monitoring region \(id)")
            performOnLocationManagerThread {
                self.locationManager.stopMonitoring(for: region!)
            }
        }
        //resetting snoozed fence
        snoozeFence(id, duration: 0)
        if wasInside {
            reconcileTrackingState(triggerTransitionType: GeofenceTransitionExit)
        }
    }
    
    func removeAllGeoNotifications() {
        removeAllGeoNotificationsInternal(notifyTransition: true)
    }

    func removeAllGeoNotificationsInternal(notifyTransition: Bool) {
        var removedActiveInside = false
        if let allStored = store.getAll() {
            removedActiveInside = allStored.contains { $0["isInside"].boolValue && isWithinTimeRange($0) }
        }
        store.clear()
        for object in monitoredRegionsSnapshot() {
            let region = object
            log("Stoping monitoring region \(region.identifier)")
            performOnLocationManagerThread {
                self.locationManager.stopMonitoring(for: region)
            }
        }
        if notifyTransition && removedActiveInside {
            reconcileTrackingState(triggerTransitionType: GeofenceTransitionExit)
        }
    }
    
    func handleTransition(_ id: String, transitionType: Int) {
        if var geoNotification = store.findById(id) {
            if transitionType == GeofenceTransitionEnter || transitionType == GeofenceTransitionDwell {
                geoNotification["isInside"] = true
            } else if transitionType == GeofenceTransitionExit {
                geoNotification["isInside"] = false
            }
            geoNotification["lastTransitionType"].int = transitionType
            store.addOrUpdate(geoNotification)
            reconcileTrackingState(triggerTransitionType: transitionType)

            if !isSnoozed(id) && isWithinTimeRange(geoNotification) {
                if geoNotification["notification"].isExists() && canBeTriggered(geoNotification) {
                    notifyAbout(geoNotification)
                }

                if geoNotification["url"].isExists() {
                    log("Should post to " + geoNotification["url"].stringValue)
                    if let url = URL(string: geoNotification["url"].stringValue) {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                        //formatter.locale = Locale(identifier: "en_US")

                        let transitionName: String
                        if transitionType == GeofenceTransitionEnter {
                            transitionName = "ENTER"
                        } else if transitionType == GeofenceTransitionExit {
                            transitionName = "EXIT"
                        } else if transitionType == GeofenceTransitionDwell {
                            transitionName = "DWELL"
                        } else {
                            transitionName = "UNKNOWN"
                        }

                        let jsonDict = ["geofenceId": geoNotification["id"].stringValue, "transition": transitionName, "date": dateFormatter.string(from: Date())]
                        let jsonData = try! JSONSerialization.data(withJSONObject: jsonDict, options: [])
                        
                        var request = URLRequest(url: url)
                        request.httpMethod = "post"
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue(geoNotification["authorization"].stringValue, forHTTPHeaderField: "Authorization")
                        request.httpBody = jsonData
                        
                        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                            if let error = error {
                                print("error:", error)
                                return
                            }
                            
                            do {
                                guard let data = data else { return }
                                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject] else { return }
                                print("json:", json)
                            } catch {
                                print("error:", error)
                            }
                        }
                        task.resume()
                    } else {
                        log("Invalid callback url for geofence \(id)")
                    }
                }

                var callbackGeoNotification = geoNotification
                callbackGeoNotification["transitionType"].int = transitionType
                callbackGeoNotification["lastTransitionType"].int = transitionType
                NotificationCenter.default.post(
                    name: Notification.Name(rawValue: "handleTransition"),
                    object: callbackGeoNotification.rawString(String.Encoding.utf8.rawValue, options: [])
                )
            }
        } else {
            reconcileTrackingState(triggerTransitionType: transitionType)
        }
    }
    
    func canBeTriggered(_ geo: JSON) -> Bool {
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.date(from: dateStr)
    }

    func reconcileMonitoredGeofencesAndState() {
        migrateLegacyTransitionTypeCorruption()
        if let allStored = store.getAll() {
            for geo in allStored {
                let id = geo["id"].stringValue
                if id.isEmpty {
                    continue
                }

                if getMonitoredRegion(id) == nil {
                    let location = CLLocationCoordinate2DMake(
                        geo["latitude"].doubleValue,
                        geo["longitude"].doubleValue
                    )
                    let radius = geo["radius"].doubleValue as CLLocationDistance
                    let region = CLCircularRegion(center: location, radius: radius, identifier: id)
                    var transitionType = geo["transitionType"].intValue
                    if transitionType == 0 {
                        transitionType = GeofenceTransitionEnter | GeofenceTransitionExit
                    }
                    region.notifyOnEntry = 0 != transitionType & GeofenceTransitionEnter
                    region.notifyOnExit = 0 != transitionType & GeofenceTransitionExit
                    performOnLocationManagerThread {
                        self.locationManager.startMonitoring(for: region)
                    }
                }

                if let monitoredRegion = getMonitoredRegion(id) {
                    performOnLocationManagerThread {
                        self.locationManager.requestState(for: monitoredRegion)
                    }
                }
            }
        }

        reconcileTrackingState()
    }

    func reconcileTrackingState(triggerTransitionType: Int? = nil) {
        let hasActiveInsideGeofence = hasActiveInsideGeofence()
        let wasActiveInside = defaults.bool(forKey: lastActiveInsideKey)

        if triggerTransitionType == GeofenceTransitionExit && !hasActiveInsideGeofence {
            schedulePendingExit()
            return
        }

        if hasActiveInsideGeofence {
            cancelPendingExit()
        }

        if let transitionType = triggerTransitionType {
            postCompanionTransition(transitionType: transitionType, hasActiveInsideGeofence: hasActiveInsideGeofence)
            defaults.set(hasActiveInsideGeofence, forKey: lastActiveInsideKey)
            return
        }

        if hasActiveInsideGeofence && !wasActiveInside {
            postCompanionTransition(transitionType: GeofenceTransitionEnter, hasActiveInsideGeofence: true)
            defaults.set(true, forKey: lastActiveInsideKey)
            return
        }

        if !hasActiveInsideGeofence && wasActiveInside {
            if let pendingExitAt = defaults.object(forKey: pendingExitAtKey) as? TimeInterval,
               pendingExitAt <= Date().timeIntervalSince1970 {
                cancelPendingExit()
                postCompanionTransition(transitionType: GeofenceTransitionExit, hasActiveInsideGeofence: false)
                defaults.set(false, forKey: lastActiveInsideKey)
            } else {
                schedulePendingExit()
            }
        }
    }

    func hasActiveInsideGeofence() -> Bool {
        if let allStored = store.getAll() {
            for geo in allStored {
                if geo["isInside"].boolValue && isWithinTimeRange(geo) {
                    return true
                }
            }
        }
        return false
    }

    func postCompanionTransition(transitionType: Int, hasActiveInsideGeofence: Bool) {
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: AppGeofenceTrackingTransition),
            object: nil,
            userInfo: [
                GeofenceTrackingTransitionTypeKey: transitionType,
                GeofenceTrackingHasActiveInsideKey: hasActiveInsideGeofence
            ]
        )
    }

    func schedulePendingExit() {
        let now = Date().timeIntervalSince1970
        let existingDeadline = defaults.object(forKey: pendingExitAtKey) as? TimeInterval
        let pendingExitAt: TimeInterval
        if let deadline = existingDeadline, deadline > now {
            pendingExitAt = deadline
        } else {
            pendingExitAt = now + exitDebounceSeconds
        }
        let remainingDelay = max(0, pendingExitAt - now)
        defaults.set(pendingExitAt, forKey: pendingExitAtKey)
        pendingExitWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.performSerialized {
                guard let scheduledExit = self.defaults.object(forKey: self.pendingExitAtKey) as? TimeInterval,
                      scheduledExit <= Date().timeIntervalSince1970 else {
                    return
                }

                if !self.hasActiveInsideGeofence() {
                    self.postCompanionTransition(transitionType: GeofenceTransitionExit, hasActiveInsideGeofence: false)
                    self.defaults.set(false, forKey: self.lastActiveInsideKey)
                }
                self.cancelPendingExit()
            }
        }

        pendingExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
    }

    func cancelPendingExit() {
        pendingExitWorkItem?.cancel()
        pendingExitWorkItem = nil
        defaults.removeObject(forKey: pendingExitAtKey)
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
        snoozedFences[id] = NSTimeIntervalSince1970 + duration
    }
    
    func isSnoozed(_ id: String?) -> Bool {
        guard let id = id, let fenceTime = snoozedFences[id] else {
            return false
        }
        return fenceTime > NSTimeIntervalSince1970
    }
    
    func checkTransition(_ location: CLLocation) {
        if let allStored = store.getAll() {
            for var json in allStored {
                let radius = json["radius"].doubleValue as CLLocationDistance
                let coord = CLLocation(latitude: json["latitude"].doubleValue, longitude: json["longitude"].doubleValue)
                let transitionMask = json["transitionType"].intValue
                
                if location.distance(from: coord) <= radius {
                    if !json["isInside"].boolValue {
                        if (transitionMask & GeofenceTransitionEnter) != 0 {
                            handleTransition(json["id"].stringValue, transitionType: 1)
                        }
                        json["isInside"] = true
                        store.addOrUpdate(json)
                    }
                } else {
                    if json["isInside"].boolValue {
                        if (transitionMask & GeofenceTransitionExit) != 0 {
                            handleTransition(json["id"].stringValue, transitionType: 2)
                        }
                        json["isInside"] = false
                        store.addOrUpdate(json)
                    }
                }
            }
        }
    }

    func migrateLegacyTransitionTypeCorruption() {
        guard let allStored = store.getAll() else {
            return
        }

        for var geo in allStored {
            let id = geo["id"].stringValue
            if id.isEmpty {
                continue
            }

            guard let region = getMonitoredRegion(id) as? CLCircularRegion else {
                continue
            }

            let currentTransitionType = geo["transitionType"].intValue
            var recoveredTransitionType = 0
            if region.notifyOnEntry {
                recoveredTransitionType |= GeofenceTransitionEnter
            }
            if region.notifyOnExit {
                recoveredTransitionType |= GeofenceTransitionExit
            }
            if (currentTransitionType & GeofenceTransitionDwell) != 0 {
                recoveredTransitionType |= GeofenceTransitionDwell
            }

            if recoveredTransitionType != 0 && recoveredTransitionType != currentTransitionType {
                if currentTransitionType == GeofenceTransitionEnter
                    || currentTransitionType == GeofenceTransitionExit
                    || currentTransitionType == GeofenceTransitionDwell {
                    geo["lastTransitionType"].int = currentTransitionType
                }
                geo["transitionType"].int = recoveredTransitionType
                store.addOrUpdate(geo)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            log("update location skipped: no locations provided")
            return
        }

        log("update location \(location)")
        performSerialized {
            if self.isActive {
                self.checkTransition(location)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("fail with error: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log("deferred fail error: \(String(describing: error))")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log("Entering region \(region.identifier)")
        performSerialized {
            self.handleTransition(region.identifier, transitionType: GeofenceTransitionEnter)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log("Exiting region \(region.identifier)")
        performSerialized {
            self.handleTransition(region.identifier, transitionType: GeofenceTransitionExit)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        if region is CLCircularRegion {
            let lat = (region as! CLCircularRegion).center.latitude
            let lng = (region as! CLCircularRegion).center.longitude
            let radius = (region as! CLCircularRegion).radius
            
            log("Starting monitoring for region \(region) lat \(lat) lng \(lng) of radius \(radius)")
        }
        performOnLocationManagerThread {
            self.locationManager.requestState(for: region)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        log("State for region " + region.identifier)
        performSerialized {
            guard var geoNotification = self.store.findById(region.identifier) else {
                self.reconcileTrackingState()
                return
            }

            let wasInside = geoNotification["isInside"].boolValue
            let isInside = state == .inside
            if wasInside != isInside {
                geoNotification["isInside"] = isInside
                self.store.addOrUpdate(geoNotification)
                let transitionType = isInside ? GeofenceTransitionEnter : GeofenceTransitionExit
                self.reconcileTrackingState(triggerTransitionType: transitionType)
            } else {
                self.reconcileTrackingState()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let regionId = region?.identifier ?? "<unknown>"
        log("Monitoring region " + regionId + " failed \(error)" )
        var payload: [String: Any] = [
            "regionId": regionId,
            "message": error.localizedDescription
        ]
        payload["code"] = (error as NSError).code
        if let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let payloadJson = String(data: payloadData, encoding: .utf8) {
            NotificationCenter.default.post(
                name: Notification.Name(rawValue: GeofenceMonitoringErrorNotification),
                object: payloadJson
            )
        }
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
            performSerialized {
                self.snoozeFence(response.notification.request.identifier, duration: 86400)
            }
        case "Delete":
            performSerialized {
                self.snoozeFence(response.notification.request.identifier, duration: 300)
            }
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
