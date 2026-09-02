# Cordova Geofence Plugin

Plugin to monitor circular geofences using mobile devices. The purpose is to notify user if crossing the boundary of the monitored geofence.

*Geofences persist after device reboot. You do not have to open your app first to monitor added geofences*

## Example applications

Check out our example applications:

* https://github.com/cowbell/ionic-geofence built with [Ionic](http://ionic.io/) framework
* https://github.com/tsubik/ionic2-geofence built with [Ionic 2](http://ionic.io/2) framework
* https://github.com/cowbell/ember-geofence built with [Ember.js](http://emberjs.com/), [Cordova](https://cordova.apache.org/), [Material Design](https://www.google.com/design/spec/material-design/introduction.html)

## Installation

From master
```
cordova plugin add https://github.com/cowbell/cordova-plugin-geofence
```

Latest stable version

```
cordova plugin add cordova-plugin-geofence
```

## Removing the Plugin from project

Using cordova CLI

```
cordova plugin rm cordova-plugin-geofence
```

## Supported Platforms

- Android
- iOS >=7.0
- Windows Phone 8.1
    - using Universal App (cordova windows platform)
    - using Silverlight App (cordova wp8 platform retargeted to WP 8.1)

## Known Limitations

**This plugin is a wrapper on devices' native APIs** which mean it comes with **limitations of those APIs**.

### Geofence Limit

There are certain limits of geofences that you can set in your application depends on the platform of use.

- iOS - 20 geofences
- Android - 100 geofences

### Javascript background execution

This is known limitation. When in background your app may/will be suspended to not use system resources.
Therefore, **any javascript code won't run**, only background services can run in the background. Local
notification when user crosses a geofence region will still work, but any custom javascript code won't.
If you want to perform a custom action on geofence crossing, [try to write it in native code](#listening-for-geofence-transitions-in-native-code).

### Companion background-geolocation plugin compatibility

This plugin remains the owner of geofence registration, persistence, and region monitoring.
If `cordova-background-geolocation-plugin` is also installed, this plugin can optionally notify the
companion native transition bridge so the companion plugin can decide whether to start/stop precise tracking.

Native bridge contract:

- Android optional static callback: `com.marianhello.bgloc.GeofenceTransitionHandler.onGeofenceTransition(Context,int,boolean)`
- iOS optional notification: `AppGeofenceTrackingTransition`
- Payload keys:
  - `transitionType` (`1=ENTER`, `2=EXIT`, `4=DWELL`)
  - `hasActiveInsideGeofence` (`true` when at least one currently-active monitored geofence is physically inside)
- Intended companion support: `tgptom/cordova-background-geolocation-plugin` PR #9+ transition handlers (or the corresponding released version that includes the same native bridge contract).

If the companion plugin is missing or incompatible, geofencing continues to work in standalone mode and the plugin logs diagnostics instead of crashing.

# Platform specifics

## Android

This plugin uses Google Play Services so you need to have it installed on your device.
The geofence transition `PendingIntent` passed to `GeofencingClient.addGeofences()` is mutable on Android 12+ (API 31+) as required by Play Services, while the plugin's internal alarm/navigation `PendingIntent`s remain immutable.

## iOS

Plugin is written in Swift. All xcode project options to enable swift support are set up automatically after plugin is installed thanks to
[cordova-plugin-add-swift-support](https://github.com/akofman/cordova-plugin-add-swift-support).

This standalone geofence plugin does not add `UIBackgroundModes=location` for continuous tracking.
Region monitoring is handled through Core Location geofencing APIs; if your app also needs continuous tracking, configure that in a companion background-geolocation plugin and app manifests.
The iOS plugin is loaded with `onload=true` so the Core Location delegate is installed during launch/background relaunch, but this eager native initialization does not request location permission by itself.
Time-window and delayed-exit reconciliation while iOS is suspended/terminated is best-effort and reconciles on supported wake events (`didEnterRegion`/`didExitRegion`/`requestState`/app activation).

### iOS device validation for launch-time initialization (no JS bootstrap)

1. Add at least one active geofence with a notification.
2. Fully terminate the app (swipe away from app switcher).
3. Move device/simulator across the region boundary to trigger enter/exit.
4. Confirm iOS relaunches the app in the background for the location event.
5. Confirm native reconciliation runs (`requestState` + stored state update), and a companion bridge notification (`AppGeofenceTrackingTransition`) is posted when installed.
6. Confirm this relaunch path does **not** show a new location permission prompt.
7. Confirm standalone behavior still works when companion plugin is absent (local geofence notification and no crash).

### iOS device validation for permission prompt timing

1. Fresh install with location permission not yet granted.
2. Launch app and wait for plugin eager load (`onload=true`) without calling `geofence.initialize()`: confirm no location permission prompt appears.
3. Trigger explicit app action that calls `geofence.initialize()`: confirm the app may now request location permission.

:warning: Swift 3 is not supported at the moment, the following preference has to be added in your project :

For Cordova projects

`<preference name="UseLegacySwiftLanguageVersion" value="true" />`

For PhoneGap projects

`<preference name="swift-version" value="2.3" />`

### iOS Quirks

Since iOS 10 it's mandatory to add a `NSLocationAlwaysUsageDescription` and `NSLocationWhenInUseUsageDescription` entries in the info.plist.

`NSLocationWhenInUseUsageDescription` describes the reason that the app accesses the user's location.
`NSLocationAlwaysUsageDescription` describes the reason that the app accesses the user's location when not in use (in the background).

When the system prompts the user to allow access, this string is displayed as part of the dialog box. To add this entry you can pass the variable `GEOFENCE_IN_USE_USAGE_DESCRIPTION` and `GEOFENCE_ALWAYS_USAGE_DESCRIPTION` on plugin install.

Example:
`cordova plugin add cordova-plugin-geofence --variable GEOFENCE_IN_USE_USAGE_DESCRIPTION="your usage message" --variable GEOFENCE_ALWAYS_USAGE_DESCRIPTION="your usage message"`

If you don't pass the variable, the plugin will add a default string as value.

### App submission responsibilities

Using geofencing/background location requires app-level disclosures and permission prompts that match your real behavior (for example purpose strings, privacy policy, and store data-safety/privacy declarations). This plugin cannot guarantee Apple App Store or Google Play approval by itself.

## Windows phone 8.1

Plugin can be used with both windows phone 8.1 type projects Univeral App, Silverlight App.

In order to use toast notifications you have to enable this feature in appxmanifest file either using UI in Visual Studio or edit file setting attribute **ToastCapable="true"** in **m3:VisualElements** node under Package/Applications/Application.

If you are retargeting WP 8.0 to WP 8.1 you need to register background task to perform geofence notifications. Register it via UI in Visual Studio or add following code under Package/Applications/Application/Extensions

```xml
<Extension Category="windows.backgroundTasks" EntryPoint="GeofenceComponent.GeofenceTrigger">
    <BackgroundTasks>
        <m2:Task Type="location" />
    </BackgroundTasks>
</Extension>
```

# Using the plugin

Cordova initialize plugin to `window.geofence` object.

## Methods

All methods returning promises, but you can also use standard callback functions.

- `window.geofence.initialize(onSuccess, onError)`
- `window.geofence.addOrUpdate(geofences, onSuccess, onError)`
- `window.geofence.replace(geofences, onSuccess, onError)` (iOS only; Android rejects with `UNSUPPORTED_OPERATION`)
- `window.geofence.remove(geofenceId, onSuccess, onError)`
- `window.geofence.removeAll(onSuccess, onError)`
- `window.geofence.getWatched(onSuccess, onError)`

For listening of geofence transistion you can override onTransitionReceived method
- `window.geofence.onTransitionReceived(geofences)`
- `window.geofence.onMonitoringError(error)` (iOS; monitoring failures surfaced from native Core Location)

## Constants

- `TransitionType.ENTER` = 1
- `TransitionType.EXIT` = 2
- `TransitionType.BOTH` = 3
- `TransitionType.DWELL` = 4

## Error Codes

Both `onError` function handler and promise rejection take `error` object as an argument.

```
error: {
    code: String,
    message: String
}
```

Error codes:

- `UNKNOWN`
- `PERMISSION_DENIED`
- `GEOFENCE_NOT_AVAILABLE`
- `GEOFENCE_LIMIT_EXCEEDED`
- `UNSUPPORTED_OPERATION`

## Plugin initialization

The plugin is not available until `deviceready` event is fired.

```javascript
document.addEventListener('deviceready', function () {
    // window.geofence is now available
    window.geofence.initialize().then(function () {
        console.log("Successful initialization");
    }, function (error) {
        console.log("Error", error);
    });
}, false);
```

Initialization process is responsible for requesting necessary permissions (including Always Location when required by your app flow).
If required permissions are not granted then initialization fails with error message.

## Adding new geofence to monitor

```javascript
window.geofence.addOrUpdate({
    id:             String,         // A unique identifier of geofence
    latitude:       Number,         // Geo latitude of geofence
    longitude:      Number,         // Geo longitude of geofence
    radius:         Number,         // Radius of geofence in meters
    transitionType: Number,         // Type of transition 1 - Enter, 2 - Exit, 3 - Both
    startTime:      Date,           // (Optional) JavaScript Date object for when the geofence should become enabled (iOS and Android only)
    endTime:        Date,           // (Optional) JavaScript Date object for when the geofence should become disabled (iOS and Android only)
    notification: {                 // Notification object
        id:             Number,     // (Optional) should be integer, id of notification
        title:          String,     // Title of notification
        text:           String,     // Text of notification
        smallIcon:      String,     // Small icon showed in notification area, only res URI
        icon:           String,     // icon showed in notification drawer
        color:          String,     // Notification color, only hex
        openAppOnClick: Boolean,    // is main app activity should be opened after clicking on notification
        frequency:      Number,     // (Optional) Seconds required between retriggering a fence.
        vibration:      [Integer],  // (Optional) vibration pattern - see description
        data:           Object      // (Optional) Custom object associated with notification
    }
}).then(function () {
    console.log('Geofence successfully added');
}, function (error) {
    console.log('Adding geofence failed', error);
});
```
Adding more geofences at once
```javascript
window.geofence.addOrUpdate([geofence1, geofence2, geofence3]);
```

Geofence overrides the previously one with the same `id`.

*All geofences are stored on the device and restored to monitor after device reboot.*

Notification overrides the previously one with the same `notification.id`.

## Notification vibrations

You can set vibration pattern for the notification or disable default vibrations.

To change vibration pattern set `vibrate` property of `notification` object in geofence.

### Examples

```
//disable vibrations
notification: {
    vibrate: [0]
}
```

```
//Vibrate for 1 sec
//Wait for 0.5 sec
//Vibrate for 2 sec
notification: {
    vibrate: [1000, 500, 2000]
}
```

### Platform quirks

Fully working only on Android.

On iOS vibration pattern doesn't work. Plugin only allow to vibrate with default system pattern.

Windows Phone - current status is TODO

## Notification icons

To set notification icons use `icon` and `smallIcon` property in `notification` object.

As a value you can enter:
- name of native resource or your application resource e.g. `res://ic_menu_mylocation`, `res://icon`, `res://ic_menu_call`
- relative path to file in `www` directory e.g. `file://img/ionic.png`

`smallIcon` - supports only resources URI

### Examples

```
notification: {
    smallIcon: 'res://my_location_icon',
    icon: 'file://img/geofence.png'
}
```

### Platform quirks

Works only on Android platform so far.

## Removing

Removing single geofence
```javascript
window.geofence.remove(geofenceId)
    .then(function () {
        console.log('Geofence sucessfully removed');
    }
    , function (error){
        console.log('Removing geofence failed', error);
    });
```
Removing more than one geofence at once.
```javascript
window.geofence.remove([geofenceId1, geofenceId2, geofenceId3]);
```

## Removing all geofences

```javascript
window.geofence.removeAll()
    .then(function () {
        console.log('All geofences successfully removed.');
    }
    , function (error) {
        console.log('Removing geofences failed', error);
    });
```

## Getting watched geofences from device

```javascript
window.geofence.getWatched().then(function (geofencesJson) {
    var geofences = JSON.parse(geofencesJson);
});
```

## Listening for geofence transitions

```javascript
window.geofence.onTransitionReceived = function (geofences) {
    geofences.forEach(function (geo) {
        console.log('Geofence transition detected', geo);
    });
};
```

## Listening for geofence transitions in native code

### Android

The plugin delivers JavaScript transition events through `window.geofence.onTransitionReceived`.
For cross-plugin native integration with `cordova-background-geolocation-plugin`, use the compatibility contract documented above.

Android note: receiver/service coordination uses non-exact alarms (`AlarmManager.setWindow`) for window-boundary/exit reconciliation, so timing near boundaries is best-effort and reconciled again on the next wake/transition.

## When the app is opened via Notification click

Android, iOS only

```javascript
window.geofence.onNotificationClicked = function (notificationData) {
    console.log('App opened from Geo Notification!', notificationData);
};
```

# Example usage

Adding geofence to monitor entering Gliwice city center area of radius 3km with a fixed start and end time.

```javascript
window.geofence.addOrUpdate({
    id:             "69ca1b88-6fbe-4e80-a4d4-ff4d3748acdb",
    latitude:       50.2980049,
    longitude:      18.6593152,
    radius:         3000,
    transitionType: TransitionType.ENTER,
    startTime:      new Date('1/23/2017 11:00 AM PST'),
    endTime:        new Date('1/27/2017 3:00 PM PST'),
    notification: {
        id:             1,
        title:          "Welcome in Gliwice",
        text:           "You just arrived to Gliwice city center.",
        openAppOnClick: true,
        frequency:      60
    }
}).then(function () {
    console.log('Geofence successfully added');
}, function (reason) {
    console.log('Adding geofence failed', reason);
})
```

# Development

## Installation

- git clone https://github.com/cowbell/cordova-plugin-geofence
- change into the new directory
- `npm install`

## Running tests

- Start emulator
- `cordova-paramedic --platform android --plugin .`

### Testing on iOS

Before you run `cordova-paramedic` install `npm install -g ios-sim`

### Troubleshooting

Add `--verbose` at the end of `cordova-paramedic` command.

## License

This software is released under the [Apache 2.0 License](http://opensource.org/licenses/Apache-2.0).

© 2014-2017 Cowbell-labs. All rights reserved
