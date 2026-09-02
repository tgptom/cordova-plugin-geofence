const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

const androidStorage = read('src/android/LocalStorage.java');
assert(
  androidStorage.includes('LOCALSTORAGE_ID + " = ?"'),
  'Android LocalStorage must use parameterized where clauses for writes/deletes'
);
assert(
  !androidStorage.includes("LOCALSTORAGE_ID + \"='\""),
  'Android LocalStorage must not concatenate SQL where clause values directly'
);

const androidCommand = read('src/android/AbstractGoogleServiceCommand.java');
assert(
  androidCommand.includes('CommandExecuted(new RuntimeException("Google Play services connection failed: " + connectionResult));'),
  'Android command layer must complete command with error when Google Play services connection fails'
);

const executor = read('src/android/GoogleServiceCommandExecutor.java');
assert(
  executor.includes('private final Object lock = new Object();'),
  'Android command executor must synchronize queue state'
);
assert(
  executor.includes('synchronized (lock)'),
  'Android command executor must lock queue operations'
);

const receiver = read('src/android/ReceiveTransitionsReceiver.java');
assert(
  receiver.includes('new JobInfo.Builder(jobId, new ComponentName(context, TransitionJobService.class))'),
  'Transition URL jobs must use non-constant job IDs to avoid replacing pending jobs'
);
assert(
  !receiver.includes('new JobInfo.Builder(1, new ComponentName(context, TransitionJobService.class))'),
  'Transition URL jobs must not use constant JobScheduler IDs'
);

const jobService = read('src/android/TransitionJobService.java');
assert(
  jobService.includes('JSONObject payload = new JSONObject();'),
  'TransitionJobService must serialize callback body as JSON object'
);
assert(
  jobService.includes('if (responseCode < 200 || responseCode >= 300)'),
  'TransitionJobService must fail non-success HTTP status codes for retry'
);
assert(
  jobService.includes('if (!"http".equalsIgnoreCase(protocol) && !"https".equalsIgnoreCase(protocol))'),
  'TransitionJobService must reject non-http(s) callback schemes'
);

const pluginAndroid = read('src/android/GeofencePlugin.java');
assert(
  pluginAndroid.includes('openAppBackgroundLocationSettings();'),
  'Android initialize flow must hand off Android 11+ background permission to app settings'
);
assert(
  pluginAndroid.includes('BACKGROUND_LOCATION_SETTINGS_REQUIRED'),
  'Android initialize flow must surface explicit background settings denial reason'
);
assert(
  !pluginAndroid.includes('&& hasNotificationPermissionIfRequired()'),
  'Android initialize permission success must not require notification permission'
);

const pluginIOS = read('src/ios/GeofencePlugin.swift');
assert(
  pluginIOS.includes('weak var previousNotificationDelegate: UNUserNotificationCenterDelegate?'),
  'iOS notification center delegate must preserve previous delegate for coexistence'
);
assert(
  pluginIOS.includes('delegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)'),
  'iOS notification delegate should forward non-plugin foreground notifications'
);
assert(
  pluginIOS.includes('postTransitionToServerWithRetry('),
  'iOS transition URL callback should use retry helper'
);
assert(
  pluginIOS.includes('attempt < 3'),
  'iOS transition URL callback should cap retries'
);
assert(
  pluginIOS.includes('transitionType != (GeofenceTransitionEnter | GeofenceTransitionExit)'),
  'iOS transition validation must allow ENTER/EXIT/BOTH only'
);
assert(
  !pluginIOS.includes('transitionType != GeofenceTransitionDwell'),
  'iOS transition validation must not advertise DWELL support'
);

const pluginXml = read('plugin.xml');
assert(
  !pluginXml.includes('<platform name="windows">') && !pluginXml.includes('<platform name="wp8">'),
  'Packaging metadata should not include obsolete Windows/WP8 platform artifacts'
);

const pkg = JSON.parse(read('package.json'));
assert.deepStrictEqual(pkg.cordova.platforms, ['android', 'ios'], 'Package metadata should target Android and iOS');
