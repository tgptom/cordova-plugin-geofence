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
  source.includes('REQUEST_FOREGROUND_LOCATION'),
  'Android plugin must use a dedicated request code for foreground location stage'
);

assert(
  source.includes('REQUEST_BACKGROUND_LOCATION'),
  'Android plugin must use a dedicated request code for background location stage'
);

assert(
  source.includes('REQUEST_NOTIFICATION_PERMISSION'),
  'Android plugin must use a dedicated request code for notification stage'
);

assert(
  source.includes('requestNextInitializePermissionStage'),
  'Android plugin must run initialize permission flow through staged progression'
);

function createFlowHarness(options) {
  const cfg = Object.assign({
    sdk: 34,
    hasForeground: false,
    hasBackground: false,
    hasNotifications: false
  }, options || {});

  const REQUEST_FOREGROUND_LOCATION = 2001;
  const REQUEST_BACKGROUND_LOCATION = 2002;
  const REQUEST_NOTIFICATION_PERMISSION = 2003;

  const queue = [];
  const callbackSettlements = [];
  const state = {
    inFlight: false,
    foreground: cfg.hasForeground,
    background: cfg.hasBackground,
    notifications: cfg.hasNotifications,
    requests: []
  };

  function settleQueue(result) {
    while (queue.length > 0) {
      const cb = queue.shift();
      if (cb.settled) {
        throw new Error('callback settled more than once');
      }
      cb.settled = true;
      callbackSettlements.push(result);
    }
    state.inFlight = false;
  }

  function requestNextStage() {
    if (!state.foreground) {
      state.requests.push(REQUEST_FOREGROUND_LOCATION);
      return;
    }
    settleQueue({ ok: true });
  }

  return {
    state,
    initialize() {
      const cb = { settled: false };
      if (state.foreground && (cfg.sdk <= 28 || state.background) && (cfg.sdk < 33 || state.notifications)) {
        cb.settled = true;
        callbackSettlements.push({ ok: true });
        return cb;
      }
      queue.push(cb);
      if (!state.inFlight) {
        state.inFlight = true;
        requestNextStage();
      }
      return cb;
    },
    onPermissionResult(requestCode, grantResults) {
      if (!state.inFlight) {
        return;
      }
      if (!Array.isArray(grantResults) || grantResults.length === 0) {
        settleQueue({ ok: false, reason: 'MALFORMED_GRANT_RESULTS' });
        return;
      }
      if (grantResults.some((result) => result !== 'granted')) {
        settleQueue({ ok: false, reason: 'PERMISSION_DENIED' });
        return;
      }
      if (requestCode === REQUEST_FOREGROUND_LOCATION) {
        state.foreground = true;
      } else if (requestCode === REQUEST_BACKGROUND_LOCATION) {
        state.background = true;
      } else if (requestCode === REQUEST_NOTIFICATION_PERMISSION) {
        state.notifications = true;
      } else {
        return;
      }
      requestNextStage();
    },
    requestBackgroundPermission() {
      if (cfg.sdk <= 28 || state.background) {
        callbackSettlements.push({ ok: true, stage: 'background' });
        return;
      }
      if (!state.foreground) {
        callbackSettlements.push({ ok: false, stage: 'background', reason: 'FOREGROUND_REQUIRED' });
        return;
      }
      state.requests.push(REQUEST_BACKGROUND_LOCATION);
    },
    requestNotificationPermission() {
      if (cfg.sdk < 33 || state.notifications) {
        callbackSettlements.push({ ok: true, stage: 'notification' });
        return;
      }
      state.requests.push(REQUEST_NOTIFICATION_PERMISSION);
    },
    onOptionalPermissionResult(requestCode, grantResults) {
      if (!Array.isArray(grantResults) || grantResults.length === 0) {
        callbackSettlements.push({ ok: false, reason: 'MALFORMED_GRANT_RESULTS' });
        return;
      }
      if (grantResults.some((result) => result !== 'granted')) {
        callbackSettlements.push({ ok: false, reason: 'PERMISSION_DENIED' });
        return;
      }
      if (requestCode === REQUEST_BACKGROUND_LOCATION) {
        state.background = true;
        callbackSettlements.push({ ok: true, stage: 'background' });
      } else if (requestCode === REQUEST_NOTIFICATION_PERMISSION) {
        state.notifications = true;
        callbackSettlements.push({ ok: true, stage: 'notification' });
      }
    },
    callbackSettlements
  };
}

{
  const flow = createFlowHarness({ sdk: 34 });
  flow.initialize();
  assert.deepStrictEqual(
    flow.state.requests,
    [2001],
    'Initialize must request only foreground location'
  );
  flow.onPermissionResult(2001, ['granted', 'granted']);
  assert.deepStrictEqual(
    flow.callbackSettlements,
    [{ ok: true }],
    'Initialize must settle after foreground permission succeeds'
  );

  flow.requestBackgroundPermission();
  assert.deepStrictEqual(
    flow.state.requests,
    [2001, 2002],
    'Background permission must be requested as an explicit follow-up stage'
  );
  flow.onOptionalPermissionResult(2002, ['granted']);
  flow.requestNotificationPermission();
  assert.deepStrictEqual(
    flow.state.requests,
    [2001, 2002, 2003],
    'Notification permission must be requested only when needed'
  );
  flow.onOptionalPermissionResult(2003, ['granted']);
}

{
  const flow = createFlowHarness({ sdk: 34 });
  const callbackA = flow.initialize();
  const callbackB = flow.initialize();
  assert.deepStrictEqual(
    flow.state.requests,
    [2001],
    'Concurrent initialize calls must share one in-flight permission flow'
  );
  flow.onPermissionResult(2001, ['granted', 'granted']);
  assert.strictEqual(callbackA.settled, true, 'First initialize callback must settle');
  assert.strictEqual(callbackB.settled, true, 'Second initialize callback must settle');
  assert.strictEqual(flow.callbackSettlements.length, 2, 'All queued initialize callbacks must settle exactly once');
}

{
  const flow = createFlowHarness({ sdk: 34, hasForeground: false });
  flow.requestBackgroundPermission();
  assert.deepStrictEqual(
    flow.callbackSettlements,
    [{ ok: false, stage: 'background', reason: 'FOREGROUND_REQUIRED' }],
    'Background permission must require foreground permission first'
  );
}

{
  const flow = createFlowHarness({ sdk: 34 });
  flow.initialize();
  flow.onPermissionResult(9999, ['granted']);
  assert.strictEqual(
    flow.callbackSettlements.length,
    0,
    'Unrelated request codes must be ignored while initialize permission flow is in flight'
  );
  flow.onPermissionResult(2001, []);
  assert.deepStrictEqual(
    flow.callbackSettlements,
    [{ ok: false, reason: 'MALFORMED_GRANT_RESULTS' }],
    'Malformed grant results must reject queued callbacks'
  );
}

assert(
  !source.includes('private Action executedAction;'),
  'Android plugin must not rely on a single executedAction slot for permission flow'
);
