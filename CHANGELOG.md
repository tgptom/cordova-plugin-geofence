# ChangeLog

## Version 0.8.1 - Unreleased

- Bump plugin version in package and plugin metadata for release preparation.
- Android initialize permissions now use staged foreground/background flow, with Android 11+ app-settings handoff for "Allow all the time", timeout/cancellation handling, and optional notification permission on Android 13+.
- Android transition webhooks now use safe JSON payload serialization, URL scheme validation (HTTPS by default; HTTP opt-in for development), bounded retries, and unique JobScheduler IDs per transition.
- iOS now rejects DWELL transition configuration (Core Location geofencing supports only ENTER/EXIT), and notification delegate handling forwards unrelated notifications to previously installed delegates.
- Removed unsupported Windows/WP8 plugin metadata/artifacts from package contents.

## Version 0.7.0 - 14.05.2017

- Adding/removing geofences now throw errors correctly
- Error codes [Details](https://github.com/cowbell/cordova-plugin-geofence#error-codes)
- Fix android 6.0 crashes when user denied location permissions [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/196)
- Fix notification overrides (android) [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/195)
- Fix occasional crashes when adding geofences (android) [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/196)
- Support for NSLocationAlwaysUsageDescription and NSLocationWhenInUseUsageDescription (iOS) [Details](https://github.com/cowbell/cordova
- Support for Swift 2.3, XCode 8.0-8.2
- Swift support handling delegated to [respective plugin](https://github.com/akofman/cordova-plugin-add-swift-support)-plugin-geofence/pull/194)

## Version 0.6.0 - 15.04.2016

- Support for Android 6 new permission acquiring model
- Support for Cordova 6.0
- Fix for notification permissions on iOS 8
- Removed unnecessary WRITE_STORAGE permissions on Android
- initialize method fails when required permissions are not granted

## Version 0.5.0 - 09.11.2015

- Support for new Google API
- Support for Xcode 7.0, swift 2.0
- Android native code broadcast intent. [Details](https://github.com/cowbell/cordova-plugin-geofence#listening-for-geofence-transitions-in-native-code)
- iOS - using SwiftyJson instead of json.swift library
- Fixing received transition type for transitionType=BOTH. [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/91)
- Parameters coercion. [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/84)
- Fixed displaying location permission dialog only when `initialize` function is called. [Details](https://github.com/cowbell/cordova-plugin-geofence/issues/85)

## Version 0.4.2 - 02.08.2015

- fixed Promise bug

## Version 0.4.1 - 07.07.2015

- dependant plugins ids updated

## Version 0.4.0 - 06.05.2015

- Support for Xcode 6.3 and swift 1.2, swift < 1.2 is not supported
- Support for Cordova 5.0
- Add missing namespace decleration for M2 Windows Phone
- Notification for monitored region can be optional
- Vibrations on/off for iOS
- Vibration patterns for android

    ```
    //Vibrate for 1 sec
    //Wait for 0.5 sec
    //Vibrate for 2 sec
    notification: {
        vibrate: [1000, 500, 2000]
    }
    ```
- Custom notification icons for android

    ```
    notification: {
        smallIcon: 'res://my_location_icon',
        icon: 'file://img/geofence.png'
    }
    ```
- `onNotificationClicked` event
- `receiveTransition` event is deprecated see `onTransitionReceived`
- Google Support and Play Services load externally
