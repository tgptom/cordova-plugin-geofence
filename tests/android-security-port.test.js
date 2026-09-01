const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const geofencePluginPath = path.join(repoRoot, 'src/android/GeofencePlugin.java');
const notifierPath = path.join(repoRoot, 'src/android/GeoNotificationNotifier.java');

const geofencePluginSource = fs.readFileSync(geofencePluginPath, 'utf8');
const notifierSource = fs.readFileSync(notifierPath, 'utf8');

assert(
  geofencePluginSource.includes('JSONObject.quote(jsonPayload)'),
  'GeofencePlugin must quote JSON payload before JS dispatch'
);
assert(
  geofencePluginSource.includes('JSON.parse('),
  'GeofencePlugin must parse quoted JSON payload in JavaScript'
);
assert(
  geofencePluginSource.includes('setTimeout(function(){'),
  'GeofencePlugin must use function-based setTimeout, not string evaluation'
);
assert(
  !geofencePluginSource.includes("setTimeout('geofence.onTransitionReceived("),
  'Geofence transition callback must not be interpolated into a setTimeout string'
);
assert(
  !geofencePluginSource.includes("setTimeout('geofence.onNotificationClicked("),
  'Notification click callback must not be interpolated into a setTimeout string'
);
assert(
  geofencePluginSource.includes('new JSONTokener(data).nextValue();'),
  'Notification click payload must be validated as JSON before dispatch'
);
assert(
  geofencePluginSource.includes('Ignoring malformed notification click payload'),
  'Malformed notification click payloads must be rejected with a log entry'
);
assert(
  geofencePluginSource.includes('Invalid geofence payload: null object'),
  'Null geofence JSON objects must be handled defensively'
);

assert(
  notifierSource.includes('PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE'),
  'Notification PendingIntent must remain immutable'
);
assert(
  !notifierSource.includes('PendingIntent.FLAG_MUTABLE'),
  'Notification PendingIntent must not be mutable'
);

const transitionPayload = [{
  id: 'g1',
  tricky: 'apostrophe \', quote ", slash \\\\, sep\u2028line\u2029para',
  codeLike: '\');globalThis.__injected=true;//'
}];
const callbackJson = JSON.stringify(transitionPayload);
const quotedJsonPayload = JSON.stringify(callbackJson);
const parsedPayload = JSON.parse(JSON.parse(quotedJsonPayload));

assert.strictEqual(
  JSON.stringify(parsedPayload),
  JSON.stringify(transitionPayload),
  'Payload containing special characters must remain inert data after quote+parse roundtrip'
);
