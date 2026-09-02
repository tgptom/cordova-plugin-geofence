const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const geofencePluginPath = path.join(repoRoot, 'src/android/GeofencePlugin.java');
const notifierPath = path.join(repoRoot, 'src/android/GeoNotificationNotifier.java');
const jobServicePath = path.join(repoRoot, 'src/android/TransitionJobService.java');
const receiverPath = path.join(repoRoot, 'src/android/ReceiveTransitionsReceiver.java');
const localStoragePath = path.join(repoRoot, 'src/android/LocalStorage.java');
const secureStorePath = path.join(repoRoot, 'src/android/GeoNotificationStore.java');

const geofencePluginSource = fs.readFileSync(geofencePluginPath, 'utf8');
const notifierSource = fs.readFileSync(notifierPath, 'utf8');
const jobServiceSource = fs.readFileSync(jobServicePath, 'utf8');
const receiverSource = fs.readFileSync(receiverPath, 'utf8');
const localStorageSource = fs.readFileSync(localStoragePath, 'utf8');
const secureStoreSource = fs.readFileSync(secureStorePath, 'utf8');

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

assert(
  jobServiceSource.includes('static boolean isAllowedCallbackUrl'),
  'Transition callback uploads must validate callback URL policy'
);
assert(
  receiverSource.includes('TransitionJobService.isAllowedCallbackUrl'),
  'Transition receiver must block disallowed callback URLs before scheduling jobs'
);
assert(
  receiverSource.includes('buildTransitionJobId('),
  'Transition jobs must use unique IDs instead of a fixed ID'
);
assert(
  jobServiceSource.includes('new JSONObject()'),
  'Transition upload payload must use structured JSON construction'
);
assert(
  localStorageSource.includes('LOCALSTORAGE_ID + "=?"'),
  'LocalStorage update/delete queries must use parameterized where clauses'
);
assert(
  secureStoreSource.includes('AndroidSecureAuthorizationStore'),
  'Authorization tokens must be stored outside plain geofence JSON records'
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
