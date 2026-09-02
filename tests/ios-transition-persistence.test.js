const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const iosPath = path.join(repoRoot, 'src/ios/GeofencePlugin.swift');
const jsPath = path.join(repoRoot, 'www/geofence.js');
const iosSource = fs.readFileSync(iosPath, 'utf8');
const jsSource = fs.readFileSync(jsPath, 'utf8');

assert(
  iosSource.includes('geoNotification["lastTransitionType"].int = transitionType'),
  'iOS must store transition events in a dedicated lastTransitionType field'
);

assert(
  !iosSource.includes('geoNotification["transitionType"].int = transitionType'),
  'iOS must not overwrite configured transitionType with latest runtime transition event'
);

assert(
  iosSource.includes('func migrateLegacyTransitionTypeCorruption()'),
  'iOS must include migration logic for previously corrupted transitionType values'
);

assert(
  iosSource.includes('if let js = buildSafeCallbackJs(functionName: "geofence.onTransitionReceived", jsonPayload: payload)'),
  'iOS transition callback must use JSON-safe callback delivery'
);

assert(
  iosSource.includes('if let js = buildSafeCallbackJs(functionName: "geofence.onNotificationClicked", jsonPayload: geoNotificationString)'),
  'iOS notification click callback must use JSON-safe callback delivery'
);

assert(
  !iosSource.includes("setTimeout('geofence.onTransitionReceived("),
  'iOS transition callback must not interpolate payload into setTimeout string'
);

assert(
  !iosSource.includes("setTimeout('geofence.onNotificationClicked("),
  'iOS notification callback must not interpolate payload into setTimeout string'
);

assert(
  jsSource.includes('onMonitoringError: function (error) {}'),
  'JavaScript API must expose onMonitoringError callback for native monitoring failures'
);
