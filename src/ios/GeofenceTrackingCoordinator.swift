import Foundation
import UIKit

final class GeofenceTrackingCoordinator {
    private static let nativeTransitionName = Notification.Name(rawValue: "PAPAGeofenceTrackingTransition")
    private static let pendingExitDeadlineKey = "PAPAGeofencePendingExitDeadline"
    private static let exitDelay: TimeInterval = 30

    private let store: GeoNotificationStore
    private let isSnoozed: (String) -> Bool
    private var exitWorkItem: DispatchWorkItem?
    private var windowWorkItem: DispatchWorkItem?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    init(store: GeoNotificationStore, isSnoozed: @escaping (String) -> Bool) {
        self.store = store
        self.isSnoozed = isSnoozed
    }

    func handleTransition(_ transitionType: Int) {
        runOnMain {
            if transitionType == 1 || transitionType == 4 {
                self.cancelPendingExit()
            }
            self.reconcileCurrentState(stopWhenEmpty: transitionType == 2)
        }
    }

    func reconcile() {
        runOnMain {
            self.reconcileCurrentState(stopWhenEmpty: false)
        }
    }

    private func reconcileCurrentState(stopWhenEmpty: Bool = false) {
        scheduleNextWindowBoundary()

        if (store.getAll() ?? []).isEmpty {
            if stopWhenEmpty || UserDefaults.standard.object(forKey: Self.pendingExitDeadlineKey) != nil {
                scheduleExit()
            } else {
                cancelPendingExit()
            }
            return
        }

        if hasActiveInsideGeofence() {
            cancelPendingExit()
            postNativeTransition(1, hasActiveInsideGeofence: true)
            return
        }

        if hasActiveUnknownGeofence() {
            cancelPendingExit()
            return
        }

        scheduleExit()
    }

    private func scheduleExit() {
        if exitWorkItem != nil {
            return
        }

        let defaults = UserDefaults.standard
        let storedDeadline = defaults.object(forKey: Self.pendingExitDeadlineKey) as? Double
        let deadline = storedDeadline ?? Date().timeIntervalSince1970 + Self.exitDelay
        defaults.set(deadline, forKey: Self.pendingExitDeadlineKey)

        let remaining = max(0, deadline - Date().timeIntervalSince1970)
        beginBackgroundTask()

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishPendingExit()
        }
        exitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    private func finishPendingExit() {
        exitWorkItem?.cancel()
        exitWorkItem = nil

        if hasActiveInsideGeofence() {
            cancelPendingExit()
            postNativeTransition(1, hasActiveInsideGeofence: true)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingExitDeadlineKey)
            postNativeTransition(2, hasActiveInsideGeofence: false)
            endBackgroundTask()
        }
        scheduleNextWindowBoundary()
    }

    private func cancelPendingExit() {
        exitWorkItem?.cancel()
        exitWorkItem = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingExitDeadlineKey)
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        guard backgroundTaskIdentifier == .invalid else {
            return
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "PAPAGeofenceExitDelay",
            expirationHandler: { [weak self] in
                self?.runOnMain {
                    self?.finishPendingExit()
                }
            }
        )
    }

    private func endBackgroundTask() {
        guard backgroundTaskIdentifier != .invalid else {
            return
        }

        let identifier = backgroundTaskIdentifier
        backgroundTaskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func scheduleNextWindowBoundary() {
        windowWorkItem?.cancel()
        windowWorkItem = nil

        let now = Date()
        var nextBoundary: Date?
        for geoNotification in store.getAll() ?? [] {
            for key in ["startTime", "endTime"] where geoNotification[key].isExists() {
                guard let date = parseDate(geoNotification[key].stringValue), date > now else {
                    continue
                }
                if nextBoundary == nil || date < nextBoundary! {
                    nextBoundary = date
                }
            }
        }

        guard let boundary = nextBoundary else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileCurrentState(stopWhenEmpty: false)
        }
        windowWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, boundary.timeIntervalSinceNow) + 0.05,
            execute: workItem
        )
    }

    private func hasActiveInsideGeofence() -> Bool {
        let now = Date()
        return (store.getAll() ?? []).contains { geoNotification in
            let id = geoNotification["id"].stringValue
            return geoNotification["stateKnown"].boolValue &&
                geoNotification["isInside"].boolValue &&
                !isSnoozed(id) &&
                isWithinTimeRange(geoNotification, now: now)
        }
    }

    private func hasActiveUnknownGeofence() -> Bool {
        let now = Date()
        return (store.getAll() ?? []).contains { geoNotification in
            let id = geoNotification["id"].stringValue
            return !geoNotification["stateKnown"].boolValue &&
                !isSnoozed(id) &&
                isWithinTimeRange(geoNotification, now: now)
        }
    }

    private func isWithinTimeRange(_ geoNotification: JSON, now: Date) -> Bool {
        if geoNotification["startTime"].isExists(),
            let startTime = parseDate(geoNotification["startTime"].stringValue),
            now < startTime {
            return false
        }
        if geoNotification["endTime"].isExists(),
            let endTime = parseDate(geoNotification["endTime"].stringValue),
            now >= endTime {
            return false
        }
        return true
    }

    private func parseDate(_ value: String) -> Date? {
        return parseGeofenceDate(value)
    }

    private func postNativeTransition(_ transitionType: Int, hasActiveInsideGeofence: Bool) {
        NotificationCenter.default.post(
            name: Self.nativeTransitionName,
            object: nil,
            userInfo: [
                "transitionType": transitionType,
                "hasActiveInsideGeofence": hasActiveInsideGeofence
            ]
        )
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}