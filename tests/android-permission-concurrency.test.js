const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const pluginPath = path.join(repoRoot, 'src/android/GeofencePlugin.java');
const source = fs.readFileSync(pluginPath, 'utf8');

assert(
  source.includes('pendingInitializeCallbacks'),
  'Android plugin must queue concurrent initialize callbacks while permission request is in flight'
);

assert(
  source.includes('isPermissionRequestInFlight'),
  'Android plugin must track in-flight permission request state'
);

assert(
  !source.includes('private Action executedAction;'),
  'Android plugin must not rely on a single executedAction slot for permission flow'
);
