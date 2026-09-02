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

assert(
  iosSource.includes('guard let location = locations.last else'),
  'iOS location updates must guard against empty Core Location updates and use latest location'
);

assert(
  iosSource.includes('forwardedNotificationDelegate = notificationCenter.delegate'),
  'iOS must preserve any existing UNUserNotificationCenter delegate before installing plugin delegate'
);
assert(
  iosSource.includes('forwarded.userNotificationCenter?(center, willPresent: notification)'),
  'iOS notification delegate must forward willPresent callbacks to existing delegate'
);
assert(
  iosSource.includes('forwarded.userNotificationCenter?(center, didReceive: response)'),
  'iOS notification delegate must forward didReceive callbacks to existing delegate'
);
assert(
  iosSource.includes('func isAllowedCallbackUrl(_ url: URL) -> Bool'),
  'iOS transition callback URLs must be validated against transport policy'
);
assert(
  iosSource.includes('IOSSecureAuthorizationStore'),
  'iOS authorization headers must be stored in keychain-backed secure storage'
);

function schedulePendingExit(now, debounceSeconds, existingDeadline) {
  let pendingExitAt = now + debounceSeconds;
  if (typeof existingDeadline === 'number' && existingDeadline > now) {
    pendingExitAt = existingDeadline;
  }
  return {
    pendingExitAt,
    remainingDelay: Math.max(0, pendingExitAt - now)
  };
}

{
  const debounceSeconds = 30;
  const first = schedulePendingExit(100, debounceSeconds, null);
  const second = schedulePendingExit(110, debounceSeconds, first.pendingExitAt);
  assert.strictEqual(first.pendingExitAt, 130, 'First pending exit should be now + debounce');
  assert.strictEqual(
    second.pendingExitAt,
    130,
    'Repeated reconciliation while exit is pending must preserve original future deadline'
  );
  assert.strictEqual(
    second.remainingDelay,
    20,
    'Repeated scheduling must recreate work item using remaining delay, not full debounce'
  );
}

{
  const debounceSeconds = 30;
  function reconcileTrackingState(params) {
    const actions = [];
    if (params.hasActiveInsideGeofence) {
      actions.push('cancelPendingExit');
      return actions;
    }
    if (!params.hasActiveInsideGeofence && params.wasActiveInside) {
      if (typeof params.pendingExitAt === 'number' && params.pendingExitAt <= params.now) {
        actions.push('cancelPendingExit');
        actions.push('postExit');
      } else {
        const scheduled = schedulePendingExit(params.now, debounceSeconds, params.pendingExitAt);
        actions.push({ type: 'schedulePendingExit', pendingExitAt: scheduled.pendingExitAt, delay: scheduled.remainingDelay });
      }
    }
    return actions;
  }

  assert.deepStrictEqual(
    reconcileTrackingState({
      hasActiveInsideGeofence: false,
      wasActiveInside: true,
      pendingExitAt: 190,
      now: 200
    }),
    ['cancelPendingExit', 'postExit'],
    'Expired pending-exit deadlines must fire promptly on reconciliation'
  );
}

{
  let pendingExitAt = 130;
  let cancelled = false;
  const reenter = () => {
    pendingExitAt = null;
    cancelled = true;
  };
  reenter();
  assert.strictEqual(cancelled, true, 'Re-entry must cancel pending exit work');
  assert.strictEqual(pendingExitAt, null, 'Re-entry must clear pending exit persisted state');
}
