package com.cowbell.cordova.geofence;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.Manifest;
import android.app.NotificationManager;


import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.PermissionHelper;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

public class GeofencePlugin extends CordovaPlugin {
    public static final String TAG = "GeofencePlugin";

    public static final String ERROR_UNKNOWN = "UNKNOWN";
    public static final String ERROR_PERMISSION_DENIED = "PERMISSION_DENIED";
    public static final String ERROR_GEOFENCE_NOT_AVAILABLE = "GEOFENCE_NOT_AVAILABLE";
    public static final String ERROR_GEOFENCE_LIMIT_EXCEEDED = "GEOFENCE_LIMIT_EXCEEDED";
    private static final int REQUEST_FOREGROUND_LOCATION = 2001;
    private static final int REQUEST_BACKGROUND_LOCATION = 2002;
    private static final int REQUEST_NOTIFICATION_PERMISSION = 2003;
    private static final int REQUEST_BACKGROUND_LOCATION_SETTINGS = 2004;
    private static final String STAGE_FOREGROUND_LOCATION = "foreground_location";
    private static final String STAGE_BACKGROUND_LOCATION = "background_location";
    private static final String STAGE_BACKGROUND_LOCATION_SETTINGS = "background_location_settings";
    private static final String STAGE_NOTIFICATIONS = "notifications";
    private static final long INITIALIZE_PERMISSION_TIMEOUT_MS = 120000L;

    private static HashMap<String, Long> snoozedFences = new HashMap<>();

    private GeoNotificationManager geoNotificationManager;
    private Context context;

    private static WeakReference<CordovaWebView> webView = null;

    private class Action {
        public String action;
        public JSONArray args;
        public CallbackContext callbackContext;

        public Action(String action, JSONArray args, CallbackContext callbackContext) {
            this.action = action;
            this.args = args;
            this.callbackContext = callbackContext;
        }
    }

    private final Object permissionRequestMutex = new Object();
    private final List<CallbackContext> pendingInitializeCallbacks = new CopyOnWriteArrayList<>();
    private final Handler permissionFlowHandler = new Handler(Looper.getMainLooper());
    private final Runnable initializeTimeoutRunnable = new Runnable() {
        @Override
        public void run() {
            synchronized (permissionRequestMutex) {
                if (!isPermissionRequestInFlight || isPluginDestroyed) {
                    return;
                }
            }
            failPendingInitializeCallbacks(buildPermissionError(
                ERROR_PERMISSION_DENIED,
                "Initialization timed out while waiting for user permission action",
                activePermissionStage,
                null,
                "INITIALIZE_TIMEOUT",
                activePermissionRequestCode
            ));
        }
    };
    private boolean isPermissionRequestInFlight = false;
    private String activePermissionStage = null;
    private int activePermissionRequestCode = -1;
    private boolean awaitingBackgroundLocationSettings = false;
    private boolean notificationPermissionStageCompleted = false;
    private final List<String> initializeWarnings = new CopyOnWriteArrayList<>();
    private volatile boolean isPluginDestroyed = false;

    /**
     * @param cordova
     *            The context of the main Activity.
     * @param webView
     *            The associated CordovaWebView.
     */
    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        super.initialize(cordova, webView);
        GeofencePlugin.webView = new WeakReference<CordovaWebView>(webView);
        context = this.cordova.getActivity().getApplicationContext();
        Logger.setLogger(new Logger(TAG, context, false));
        geoNotificationManager = new GeoNotificationManager(context);
    }

    @Override
    public void onNewIntent(Intent intent) {
        String data = intent.getStringExtra("geofence.notification.data");
        if (data != null) {
            onNotificationClicked(data);
        }
    }

    @Override
    public boolean execute(final String action, final JSONArray args,
                           final CallbackContext callbackContext) throws JSONException {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                if (action.equals("addOrUpdate")) {
                    List<GeoNotification> geoNotifications = new ArrayList<GeoNotification>();
                    for (int i = 0; i < args.length(); i++) {
                        GeoNotification not = parseFromJSONObject(args.optJSONObject(i));
                        if (not != null) {
                            geoNotifications.add(not);
                        }
                    }
                    geoNotificationManager.addGeoNotifications(geoNotifications, callbackContext);
                } else if (action.equals("remove")) {
                    List<String> ids = new ArrayList<String>();
                    for (int i = 0; i < args.length(); i++) {
                        ids.add(args.optString(i));
                    }
                    geoNotificationManager.removeGeoNotifications(ids, callbackContext);
                } else if (action.equals("removeAll")) {
                    geoNotificationManager.removeAllGeoNotifications(callbackContext);
                } else if (action.equals("getWatched")) {
                    List<GeoNotification> geoNotifications = geoNotificationManager.getWatched();
                    callbackContext.success(Gson.get().toJson(geoNotifications));
                } else if (action.equals("dismissNotifications")) {
                    NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
                    for (int i = 0; i < args.length(); i++) {
                        manager.cancel(args.optInt(i));
                    }
                    callbackContext.success();
                } else if (action.equals("snooze")) {
                    snoozedFences.put(args.optString(0), System.currentTimeMillis() + args.optLong(1) * 1000);
                    callbackContext.success();
                } else if (action.equals("initialize")) {
                    initialize(callbackContext);
                } else if (action.equals("deviceReady")) {
                    Intent intent = cordova.getActivity().getIntent();
                    String data = intent.getStringExtra("geofence.notification.data");
                    if (data != null) {
                        onNotificationClicked(data);
                    }
                    callbackContext.success();
                } else {
                    callbackContext.error("Unsupported action: " + action);
                }
            }
        });

        return true;
    }

    @Override
    public void onDestroy() {
        isPluginDestroyed = true;
        permissionFlowHandler.removeCallbacks(initializeTimeoutRunnable);
        failPendingInitializeCallbacks(buildPermissionError(
            ERROR_UNKNOWN,
            "Plugin destroyed before initialization completed",
            null,
            null,
            "PLUGIN_DESTROYED",
            -1
        ));
        super.onDestroy();
    }

    public boolean execute(Action action) throws JSONException {
        return execute(action.action, action.args, action.callbackContext);
    }

    private GeoNotification parseFromJSONObject(JSONObject object) {
        if (object == null) {
            Log.e(TAG, "Invalid geofence payload: null object");
            return null;
        }
        try {
            return GeoNotification.fromJson(object.toString());
        } catch (RuntimeException e) {
            Log.e(TAG, "Failed to parse geofence payload", e);
            return null;
        }
    }

    public static void onTransitionReceived(List<GeoNotification> notifications) {
        Log.d(TAG, "Transition Event Received!");
        sendJavascript(buildSafeCallbackJs("geofence.onTransitionReceived",
            Gson.get().toJson(notifications)));
    }

    private void onNotificationClicked(String data) {
        if (data == null || data.isEmpty()) {
            return;
        }

        try {
            new JSONTokener(data).nextValue();
        } catch (JSONException e) {
            Log.e(TAG, "Ignoring malformed notification click payload", e);
            return;
        }

        sendJavascript(buildSafeCallbackJs("geofence.onNotificationClicked", data));
    }

    private static String buildSafeCallbackJs(String functionName, String jsonPayload) {
        return "setTimeout(function(){ " + functionName + "(JSON.parse("
            + JSONObject.quote(jsonPayload) + ")); },0)";
    }

    private void initialize(CallbackContext callbackContext) {
        if (callbackContext == null) {
            return;
        }

        if (isPluginDestroyed) {
            callbackContext.error(buildPermissionError(
                ERROR_UNKNOWN,
                "Plugin is destroyed",
                null,
                null,
                "PLUGIN_DESTROYED",
                -1
            ));
            return;
        }

        if (hasAllRequiredInitializePermissions()) {
            callbackContext.success(buildInitializeStatus(null));
            return;
        }

        pendingInitializeCallbacks.add(callbackContext);
        boolean shouldStartPermissionFlow = false;
        synchronized (permissionRequestMutex) {
            if (!isPermissionRequestInFlight) {
                isPermissionRequestInFlight = true;
                initializeWarnings.clear();
                notificationPermissionStageCompleted = false;
                scheduleInitializeTimeout();
                shouldStartPermissionFlow = true;
            }
        }

        if (shouldStartPermissionFlow) {
            requestNextInitializePermissionStage();
        }
    }

    public static boolean isSnoozed(String id) {
        Long fenceTime = snoozedFences.get(id);
        return fenceTime != null && fenceTime > System.currentTimeMillis();
    }

    private boolean hasPermissions(String[] permissions) {
        for (String permission : permissions) {
            if (!PermissionHelper.hasPermission(this, permission)) return false;
        }

        return true;
    }

    private boolean hasForegroundLocationPermissions() {
        return hasPermissions(new String[] {
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_FINE_LOCATION
        });
    }

    private boolean requiresBackgroundLocationPermission() {
        return Build.VERSION.SDK_INT > 28;
    }

    private boolean hasBackgroundLocationPermissionIfRequired() {
        return !requiresBackgroundLocationPermission()
            || PermissionHelper.hasPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION);
    }

    private boolean requiresNotificationPermission() {
        return Build.VERSION.SDK_INT >= 33;
    }

    private boolean hasNotificationPermissionIfRequired() {
        return !requiresNotificationPermission()
            || PermissionHelper.hasPermission(this, Manifest.permission.POST_NOTIFICATIONS);
    }

    private boolean hasAllRequiredInitializePermissions() {
        return hasForegroundLocationPermissions()
            && hasBackgroundLocationPermissionIfRequired();
    }

    private void requestNextInitializePermissionStage() {
        if (isPluginDestroyed) {
            failPendingInitializeCallbacks(buildPermissionError(
                ERROR_UNKNOWN,
                "Plugin destroyed before initialization completed",
                null,
                null,
                "PLUGIN_DESTROYED",
                -1
            ));
            return;
        }

        if (!hasForegroundLocationPermissions()) {
            requestPermissionStage(
                STAGE_FOREGROUND_LOCATION,
                REQUEST_FOREGROUND_LOCATION,
                new String[] {
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.ACCESS_FINE_LOCATION
                }
            );
            return;
        }

        if (requiresBackgroundLocationPermission()
            && !PermissionHelper.hasPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION)) {
            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                requestPermissionStage(
                    STAGE_BACKGROUND_LOCATION,
                    REQUEST_BACKGROUND_LOCATION,
                    new String[] { Manifest.permission.ACCESS_BACKGROUND_LOCATION }
                );
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                openBackgroundLocationSettings();
            }
            return;
        }

        if (requiresNotificationPermission()
            && !notificationPermissionStageCompleted
            && !PermissionHelper.hasPermission(this, Manifest.permission.POST_NOTIFICATIONS)) {
            requestPermissionStage(
                STAGE_NOTIFICATIONS,
                REQUEST_NOTIFICATION_PERMISSION,
                new String[] { Manifest.permission.POST_NOTIFICATIONS }
            );
            return;
        }

        succeedPendingInitializeCallbacks(buildInitializeStatus(null));
    }

    private boolean isPermissionFlowRequestCode(int requestCode) {
        return requestCode == REQUEST_FOREGROUND_LOCATION
            || requestCode == REQUEST_BACKGROUND_LOCATION
            || requestCode == REQUEST_NOTIFICATION_PERMISSION;
    }

    private String stageForRequestCode(int requestCode) {
        if (requestCode == REQUEST_FOREGROUND_LOCATION) {
            return STAGE_FOREGROUND_LOCATION;
        }
        if (requestCode == REQUEST_BACKGROUND_LOCATION) {
            return STAGE_BACKGROUND_LOCATION;
        }
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            return STAGE_NOTIFICATIONS;
        }
        return null;
    }

    private String[] expectedPermissionsForStage(String stage) {
        if (STAGE_FOREGROUND_LOCATION.equals(stage)) {
            return new String[] {
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION
            };
        }
        if (STAGE_BACKGROUND_LOCATION.equals(stage)) {
            return new String[] { Manifest.permission.ACCESS_BACKGROUND_LOCATION };
        }
        if (STAGE_NOTIFICATIONS.equals(stage)) {
            return new String[] { Manifest.permission.POST_NOTIFICATIONS };
        }
        return new String[0];
    }

    private JSONObject validatePermissionResult(
        int requestCode,
        String stage,
        String[] permissions,
        int[] grantResults
    ) {
        if (stage == null) {
            return buildPermissionError(
                ERROR_UNKNOWN,
                "Unknown permission request stage",
                null,
                null,
                "UNKNOWN_REQUEST_CODE",
                requestCode
            );
        }

        if (permissions == null || grantResults == null
            || permissions.length == 0 || grantResults.length == 0
            || permissions.length != grantResults.length) {
            return buildPermissionError(
                ERROR_UNKNOWN,
                "Malformed permission grant result",
                stage,
                null,
                "MALFORMED_GRANT_RESULTS",
                requestCode
            );
        }

        List<String> expectedPermissions = new ArrayList<String>();
        for (String expected : expectedPermissionsForStage(stage)) {
            expectedPermissions.add(expected);
        }
        List<String> deniedPermissions = new ArrayList<String>();

        for (int i = 0; i < permissions.length; i++) {
            String permission = permissions[i];
            if (!expectedPermissions.contains(permission)) {
                return buildPermissionError(
                    ERROR_UNKNOWN,
                    "Unexpected permission in grant result",
                    stage,
                    null,
                    "UNEXPECTED_PERMISSION_RESULT",
                    requestCode
                );
            }
            if (grantResults[i] != PackageManager.PERMISSION_GRANTED) {
                deniedPermissions.add(permission);
            }
        }

        if (!deniedPermissions.isEmpty()) {
            if (STAGE_NOTIFICATIONS.equals(stage)) {
                initializeWarnings.add("Notification permission denied. Geofence monitoring continues, but local notifications may be suppressed.");
                return null;
            }
            if (STAGE_FOREGROUND_LOCATION.equals(stage)
                && deniedPermissions.contains(Manifest.permission.ACCESS_FINE_LOCATION)) {
                return buildPermissionError(
                    ERROR_PERMISSION_DENIED,
                    "Precise location permission is required for reliable geofencing",
                    stage,
                    deniedPermissions,
                    "PRECISE_LOCATION_REQUIRED",
                    requestCode
                );
            }
            return buildPermissionError(
                ERROR_PERMISSION_DENIED,
                "Required permissions not granted",
                stage,
                deniedPermissions,
                "PERMISSION_DENIED",
                requestCode
            );
        }

        for (String expectedPermission : expectedPermissions) {
            if (!PermissionHelper.hasPermission(this, expectedPermission)) {
                return buildPermissionError(
                    ERROR_PERMISSION_DENIED,
                    "Required permissions not granted",
                    stage,
                    null,
                    "PERMISSION_STATE_MISMATCH",
                    requestCode
                );
            }
        }

        return null;
    }

    private List<CallbackContext> drainPendingInitializeCallbacks() {
        List<CallbackContext> callbacks = new ArrayList<CallbackContext>(pendingInitializeCallbacks);
        pendingInitializeCallbacks.clear();
        synchronized (permissionRequestMutex) {
            isPermissionRequestInFlight = false;
            activePermissionStage = null;
            activePermissionRequestCode = -1;
            awaitingBackgroundLocationSettings = false;
            notificationPermissionStageCompleted = false;
        }
        initializeWarnings.clear();
        permissionFlowHandler.removeCallbacks(initializeTimeoutRunnable);
        return callbacks;
    }

    private void succeedPendingInitializeCallbacks(JSONObject statusObject) {
        List<CallbackContext> callbacks = drainPendingInitializeCallbacks();
        for (CallbackContext callback : callbacks) {
            if (statusObject != null) {
                callback.success(statusObject);
            } else {
                callback.success();
            }
        }
    }

    private void failPendingInitializeCallbacks(JSONObject errorObject) {
        List<CallbackContext> callbacks = drainPendingInitializeCallbacks();
        for (CallbackContext callback : callbacks) {
            callback.error(errorObject);
        }
    }

    private JSONObject buildPermissionError(
        String code,
        String message,
        String stage,
        List<String> deniedPermissions,
        String reason,
        int requestCode
    ) {
        JSONObject errorObject = new JSONObject();
        try {
            errorObject.put("code", code);
            errorObject.put("message", message);
            if (stage != null) {
                errorObject.put("stage", stage);
            }
            if (reason != null) {
                errorObject.put("reason", reason);
            }
            if (requestCode >= 0) {
                errorObject.put("requestCode", requestCode);
            }
            if (deniedPermissions != null && !deniedPermissions.isEmpty()) {
                JSONArray denied = new JSONArray();
                for (String permission : deniedPermissions) {
                    denied.put(permission);
                }
                errorObject.put("deniedPermissions", denied);
            }
        } catch (JSONException e) {
            Log.e(TAG, "Failed to build permission error object", e);
        }
        return errorObject;
    }

    public void onRequestPermissionResult(int requestCode, String[] permissions,
                                          int[] grantResults) throws JSONException {
        if (!isPermissionFlowRequestCode(requestCode)) {
            Log.d(TAG, "Ignoring unrelated permission request code " + requestCode);
            return;
        }

        synchronized (permissionRequestMutex) {
            if (!isPermissionRequestInFlight) {
                Log.d(TAG, "Ignoring permission result for completed flow");
                return;
            }
            if (requestCode != activePermissionRequestCode) {
                failPendingInitializeCallbacks(buildPermissionError(
                    ERROR_UNKNOWN,
                    "Permission result does not match current permission stage",
                    activePermissionStage,
                    null,
                    "UNEXPECTED_REQUEST_CODE_RESULT",
                    requestCode
                ));
                return;
            }
        }

        JSONObject validationError = validatePermissionResult(
            requestCode,
            activePermissionStage,
            permissions,
            grantResults
        );
        if (validationError != null) {
            Log.d(TAG, "Permission stage failed");
            failPendingInitializeCallbacks(validationError);
            return;
        }
        if (STAGE_NOTIFICATIONS.equals(activePermissionStage)) {
            synchronized (permissionRequestMutex) {
                notificationPermissionStageCompleted = true;
            }
        }

        requestNextInitializePermissionStage();
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent intent) {
        if (requestCode != REQUEST_BACKGROUND_LOCATION_SETTINGS) {
            super.onActivityResult(requestCode, resultCode, intent);
            return;
        }
        handleBackgroundLocationSettingsReturn("activity_result");
    }

    @Override
    public void onResume(boolean multitasking) {
        super.onResume(multitasking);
        handleBackgroundLocationSettingsReturn("resume");
    }

    private void handleBackgroundLocationSettingsReturn(String trigger) {
        synchronized (permissionRequestMutex) {
            if (!isPermissionRequestInFlight || !awaitingBackgroundLocationSettings) {
                return;
            }
        }

        if (hasBackgroundLocationPermissionIfRequired()) {
            synchronized (permissionRequestMutex) {
                awaitingBackgroundLocationSettings = false;
                activePermissionStage = null;
                activePermissionRequestCode = -1;
            }
            requestNextInitializePermissionStage();
            return;
        }

        failPendingInitializeCallbacks(buildPermissionError(
            ERROR_PERMISSION_DENIED,
            "Background location permission must be set to \"Allow all the time\" in app settings",
            STAGE_BACKGROUND_LOCATION_SETTINGS,
            null,
            "BACKGROUND_LOCATION_NOT_GRANTED_IN_SETTINGS",
            REQUEST_BACKGROUND_LOCATION_SETTINGS
        ));
    }

    private void requestPermissionStage(String stage, int requestCode, String[] permissions) {
        synchronized (permissionRequestMutex) {
            activePermissionStage = stage;
            activePermissionRequestCode = requestCode;
            awaitingBackgroundLocationSettings = false;
        }
        scheduleInitializeTimeout();
        PermissionHelper.requestPermissions(this, requestCode, permissions);
    }

    private void openBackgroundLocationSettings() {
        Intent settingsIntent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        settingsIntent.setData(Uri.fromParts("package", cordova.getActivity().getPackageName(), null));
        settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        synchronized (permissionRequestMutex) {
            activePermissionStage = STAGE_BACKGROUND_LOCATION_SETTINGS;
            activePermissionRequestCode = REQUEST_BACKGROUND_LOCATION_SETTINGS;
            awaitingBackgroundLocationSettings = true;
        }
        scheduleInitializeTimeout();
        cordova.startActivityForResult(this, settingsIntent, REQUEST_BACKGROUND_LOCATION_SETTINGS);
    }

    private void scheduleInitializeTimeout() {
        permissionFlowHandler.removeCallbacks(initializeTimeoutRunnable);
        permissionFlowHandler.postDelayed(initializeTimeoutRunnable, INITIALIZE_PERMISSION_TIMEOUT_MS);
    }

    private JSONObject buildInitializeStatus(List<String> explicitWarnings) {
        JSONObject status = new JSONObject();
        JSONArray warnings = new JSONArray();
        try {
            List<String> warningsSource = explicitWarnings != null ? explicitWarnings : initializeWarnings;
            for (String warning : warningsSource) {
                warnings.put(warning);
            }
            status.put("locationPermissionGranted", hasForegroundLocationPermissions());
            status.put("backgroundLocationPermissionGranted", hasBackgroundLocationPermissionIfRequired());
            status.put("notificationPermissionRequired", requiresNotificationPermission());
            status.put("notificationPermissionGranted", hasNotificationPermissionIfRequired());
            status.put("preciseLocationRequired", true);
            status.put("preciseLocationGranted", PermissionHelper.hasPermission(this, Manifest.permission.ACCESS_FINE_LOCATION));
            status.put("warnings", warnings);
        } catch (JSONException e) {
            Log.e(TAG, "Failed to build initialize status object", e);
        }
        return status;
    }

    private static synchronized void sendJavascript(final String js) {
        if (webView == null) {
            Log.e(TAG, "Device isn't ready.");
            return;
        }

        final CordovaWebView view = webView.get();
        if (view == null) {
            return;
        }
        view.sendJavascript(js);
    }
}
