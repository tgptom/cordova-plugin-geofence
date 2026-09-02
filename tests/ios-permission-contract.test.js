const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const iosPath = path.join(repoRoot, 'src/ios/GeofencePlugin.swift');
const source = fs.readFileSync(iosPath, 'utf8');

assert(
  source.includes('transitionType DWELL is not supported on iOS because Core Location region monitoring only supports ENTER/EXIT'),
  'iOS must reject DWELL transitions with a clear platform-specific message'
);

assert(
  source.includes('previousNotificationDelegate = center.delegate'),
  'iOS notification integration must preserve previous UNUserNotificationCenter delegate'
);

assert(
  source.includes('previousDelegate.userNotificationCenter?('),
  'iOS must forward unrelated notifications to the previous delegate'
);

assert(
  source.includes('releaseNotificationDelegate()'),
  'iOS notification delegate ownership must be cleaned up when plugin manager is released'
);

assert(
  source.includes('UserDefaults.standard.bool(forKey: GeofenceDebugLoggingEnabledKey)'),
  'Sensitive logs must be gated behind explicit debug logging flag'
);
