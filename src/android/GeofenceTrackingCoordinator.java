package com.cowbell.cordova.geofence;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class GeofenceTrackingCoordinator {
    static final String ACTION_RECONCILE = "com.cowbell.cordova.geofence.ACTION_RECONCILE_TRACKING";
    static final String EXTRA_REASON = "reason";

    private static final String PREFS_NAME = "geofence_tracking_coordinator";
    private static final String PREF_INSIDE_IDS = "inside_ids";
    private static final String PREF_LAST_ACTIVE_INSIDE = "last_active_inside";
    private static final String PREF_PENDING_EXIT_AT = "pending_exit_at";

    private static final String REASON_EXIT_DEBOUNCE = "exit_debounce";
    private static final String REASON_WINDOW_BOUNDARY = "window_boundary";

    private static final long EXIT_DEBOUNCE_MS = 30_000L;
    private static final long WINDOW_ALARM_FLEX_MS = 60_000L;

    private final Context context;
    private final GeoNotificationStore store;
    private final SharedPreferences preferences;
    private final Logger logger;

    public GeofenceTrackingCoordinator(Context context) {
        this.context = context.getApplicationContext();
        this.store = new GeoNotificationStore(this.context);
        this.preferences = this.context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        this.logger = Logger.getLogger();
    }

    public void onPhysicalTransition(int transitionType, List<String> ids) {
        Set<String> insideIds = getInsideIds();
        if (transitionType == GeofenceTrackingContract.TRANSITION_ENTER
                || transitionType == GeofenceTrackingContract.TRANSITION_DWELL) {
            insideIds.addAll(ids);
        } else if (transitionType == GeofenceTrackingContract.TRANSITION_EXIT) {
            insideIds.removeAll(ids);
        }

        insideIds = sanitizeInsideIds(insideIds);
        saveInsideIds(insideIds);

        boolean hasActiveInside = hasActiveInsideGeofence(insideIds);
        if (transitionType == GeofenceTrackingContract.TRANSITION_EXIT && !hasActiveInside) {
            scheduleExitDebounce();
        } else {
            cancelExitDebounce();
            CompanionGeofenceBridge.notifyTransition(context, transitionType, hasActiveInside);
            setLastActiveInside(hasActiveInside);
        }

        scheduleNextBoundaryReconcile();
    }

    public void reconcile() {
        Set<String> insideIds = sanitizeInsideIds(getInsideIds());
        saveInsideIds(insideIds);

        boolean hasActiveInside = hasActiveInsideGeofence(insideIds);
        boolean previousActiveInside = wasLastActiveInside();

        if (hasActiveInside) {
            cancelExitDebounce();
            if (!previousActiveInside) {
                CompanionGeofenceBridge.notifyTransition(
                        context,
                        GeofenceTrackingContract.TRANSITION_ENTER,
                        true
                );
            }
            setLastActiveInside(true);
        } else if (previousActiveInside) {
            scheduleExitDebounce();
        }

        scheduleNextBoundaryReconcile();
    }

    public void onAlarm(Intent intent) {
        String reason = intent.getStringExtra(EXTRA_REASON);
        if (REASON_EXIT_DEBOUNCE.equals(reason)) {
            preferences.edit().remove(PREF_PENDING_EXIT_AT).apply();

            Set<String> insideIds = sanitizeInsideIds(getInsideIds());
            saveInsideIds(insideIds);
            boolean hasActiveInside = hasActiveInsideGeofence(insideIds);
            if (!hasActiveInside) {
                CompanionGeofenceBridge.notifyTransition(
                        context,
                        GeofenceTrackingContract.TRANSITION_EXIT,
                        false
                );
                setLastActiveInside(false);
            } else {
                setLastActiveInside(true);
            }
            scheduleNextBoundaryReconcile();
            return;
        }

        if (REASON_WINDOW_BOUNDARY.equals(reason)) {
            reconcile();
        }
    }

    private Set<String> sanitizeInsideIds(Set<String> insideIds) {
        HashSet<String> sanitized = new HashSet<String>();
        for (String id : insideIds) {
            if (store.getGeoNotification(id) != null) {
                sanitized.add(id);
            }
        }
        return sanitized;
    }

    private boolean hasActiveInsideGeofence(Set<String> insideIds) {
        for (String id : insideIds) {
            GeoNotification geoNotification = store.getGeoNotification(id);
            if (geoNotification != null && geoNotification.isWithinTimeRange()) {
                return true;
            }
        }
        return false;
    }

    private Set<String> getInsideIds() {
        Set<String> storedIds = preferences.getStringSet(PREF_INSIDE_IDS, new HashSet<String>());
        return new HashSet<String>(storedIds);
    }

    private void saveInsideIds(Set<String> insideIds) {
        preferences.edit().putStringSet(PREF_INSIDE_IDS, new HashSet<String>(insideIds)).apply();
    }

    private boolean wasLastActiveInside() {
        return preferences.getBoolean(PREF_LAST_ACTIVE_INSIDE, false);
    }

    private void setLastActiveInside(boolean value) {
        preferences.edit().putBoolean(PREF_LAST_ACTIVE_INSIDE, value).apply();
    }

    private void scheduleExitDebounce() {
        long now = System.currentTimeMillis();
        long existingPendingExitAt = preferences.getLong(PREF_PENDING_EXIT_AT, -1L);

        long triggerAt = existingPendingExitAt > now
                ? existingPendingExitAt
                : now + EXIT_DEBOUNCE_MS;

        preferences.edit().putLong(PREF_PENDING_EXIT_AT, triggerAt).apply();
        scheduleAlarm(REASON_EXIT_DEBOUNCE, triggerAt, WINDOW_ALARM_FLEX_MS);
    }

    private void cancelExitDebounce() {
        preferences.edit().remove(PREF_PENDING_EXIT_AT).apply();
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarmManager != null) {
            alarmManager.cancel(buildAlarmPendingIntent(REASON_EXIT_DEBOUNCE));
        }
    }

    private void scheduleNextBoundaryReconcile() {
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarmManager != null) {
            alarmManager.cancel(buildAlarmPendingIntent(REASON_WINDOW_BOUNDARY));
        }

        List<GeoNotification> watched = store.getAll();
        long now = System.currentTimeMillis();
        long nextBoundary = Long.MAX_VALUE;

        for (GeoNotification geoNotification : watched) {
            if (geoNotification == null) {
                continue;
            }

            if (geoNotification.getStartTime() != null) {
                long startTime = geoNotification.getStartTime().getTime();
                if (startTime > now && startTime < nextBoundary) {
                    nextBoundary = startTime;
                }
            }

            if (geoNotification.getEndTime() != null) {
                long endTime = geoNotification.getEndTime().getTime();
                if (endTime > now && endTime < nextBoundary) {
                    nextBoundary = endTime;
                }
            }
        }

        if (nextBoundary != Long.MAX_VALUE) {
            scheduleAlarm(REASON_WINDOW_BOUNDARY, nextBoundary, WINDOW_ALARM_FLEX_MS);
            if (logger != null) {
                logger.log(Log.DEBUG, "Scheduled inexact window-boundary reconcile alarm");
            }
        }
    }

    private void scheduleAlarm(String reason, long triggerAt, long windowLengthMs) {
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarmManager == null) {
            return;
        }

        PendingIntent pendingIntent = buildAlarmPendingIntent(reason);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            alarmManager.setWindow(AlarmManager.RTC_WAKEUP, triggerAt, windowLengthMs, pendingIntent);
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent);
        }
    }

    private PendingIntent buildAlarmPendingIntent(String reason) {
        Intent intent = new Intent(context, GeofenceTrackingCoordinatorReceiver.class);
        intent.setAction(ACTION_RECONCILE);
        intent.putExtra(EXTRA_REASON, reason);
        intent.setPackage(context.getPackageName());

        return PendingIntent.getBroadcast(
                context,
                reason.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    public void clearAllState() {
        cancelExitDebounce();
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarmManager != null) {
            alarmManager.cancel(buildAlarmPendingIntent(REASON_WINDOW_BOUNDARY));
        }

        preferences.edit()
                .remove(PREF_INSIDE_IDS)
                .remove(PREF_LAST_ACTIVE_INSIDE)
                .remove(PREF_PENDING_EXIT_AT)
                .apply();
    }

    public void onGeofenceRemoved(List<String> ids) {
        if (ids == null || ids.isEmpty()) {
            return;
        }

        Set<String> insideIds = getInsideIds();
        insideIds.removeAll(ids);
        saveInsideIds(insideIds);
        reconcile();
    }
}
