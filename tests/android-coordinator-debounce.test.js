const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const coordinatorPath = path.join(repoRoot, 'src/android/GeofenceTrackingCoordinator.java');
const source = fs.readFileSync(coordinatorPath, 'utf8');

assert(
  source.includes('long existingPendingExitAt = preferences.getLong(PREF_PENDING_EXIT_AT, -1L);'),
  'Coordinator must read existing pending exit deadline before rescheduling debounce'
);

assert(
  source.includes('existingPendingExitAt > now'),
  'Coordinator must preserve already scheduled pending exit deadline when it is still in the future'
);

assert(
  source.includes(': now + EXIT_DEBOUNCE_MS;'),
  'Coordinator must only create a new pending exit deadline when none is pending'
);
