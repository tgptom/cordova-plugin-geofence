package com.cowbell.cordova.geofence;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;

import com.google.android.gms.location.Geofence;

import java.lang.reflect.Method;
import java.util.Date;

public class GeofenceTrackingCoordinator extends BroadcastReceiver {
    private static final String ACTION_DELAYED_EXIT =
            "com.cowbell.cordova.geofence.DELAYED_EXIT";
    private static final String ACTION_WINDOW_EXPIRATION =
            "com.cowbell.cordova.geofence.WINDOW_EXPIRATION";
    private static final int DELAYED_EXIT_REQUEST_CODE = 41001;
    private static final int WINDOW_EXPIRATION_REQUEST_CODE = 41002;
    private static final long EXIT_DELAY_MILLIS = 30000;

    public static void handleTransition(Context context, int transitionType) {
        Context applicationContext = context.getApplicationContext();
        if (transitionType == Geofence.GEOFENCE_TRANSITION_ENTER
                || transitionType == Geofence.GEOFENCE_TRANSITION_DWELL) {
            cancelAlarm(applicationContext, ACTION_DELAYED_EXIT, DELAYED_EXIT_REQUEST_CODE);
            notifyNativeTransition(applicationContext, transitionType,
                    hasActiveInsideGeofence(applicationContext));
            return;
        }

        if (transitionType != Geofence.GEOFENCE_TRANSITION_EXIT) {
            return;
        }
        if (hasActiveInsideGeofence(applicationContext)) {
            cancelAlarm(applicationContext, ACTION_DELAYED_EXIT, DELAYED_EXIT_REQUEST_CODE);
            return;
        }

        scheduleElapsedAlarm(applicationContext, ACTION_DELAYED_EXIT,
                DELAYED_EXIT_REQUEST_CODE, EXIT_DELAY_MILLIS);
    }

    public static void refreshWindowExpiration(Context context) {
        Context applicationContext = context.getApplicationContext();
        cancelAlarm(applicationContext, ACTION_WINDOW_EXPIRATION,
                WINDOW_EXPIRATION_REQUEST_CODE);

        long now = System.currentTimeMillis();
        Long nextExpiration = null;
        GeoNotificationStore store = new GeoNotificationStore(applicationContext);
        for (GeoNotification geoNotification : store.getAll()) {
            if (geoNotification == null) {
                continue;
            }
            Date endTime = geoNotification.getEndTime();
            if (endTime != null && endTime.getTime() > now
                    && (nextExpiration == null || endTime.getTime() < nextExpiration)) {
                nextExpiration = endTime.getTime();
            }
        }
        if (nextExpiration != null) {
            scheduleWallClockAlarm(applicationContext, ACTION_WINDOW_EXPIRATION,
                    WINDOW_EXPIRATION_REQUEST_CODE, nextExpiration);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        Context applicationContext = context.getApplicationContext();
        Logger.setLogger(new Logger(GeofencePlugin.TAG, applicationContext, false));
        String action = intent != null ? intent.getAction() : null;
        if (ACTION_WINDOW_EXPIRATION.equals(action)) {
            refreshWindowExpiration(applicationContext);
        } else if (!ACTION_DELAYED_EXIT.equals(action)) {
            return;
        }

        if (!hasActiveInsideGeofence(applicationContext)) {
            notifyNativeTransition(applicationContext,
                    Geofence.GEOFENCE_TRANSITION_EXIT, false);
        }
    }

    private static boolean hasActiveInsideGeofence(Context context) {
        GeoNotificationStore store = new GeoNotificationStore(context);
        for (GeoNotification geoNotification : store.getAll()) {
            if (geoNotification != null && geoNotification.isWithinTimeRange()
                    && !GeofencePlugin.isSnoozed(geoNotification.id)
                    && (geoNotification.lastTransitionType == Geofence.GEOFENCE_TRANSITION_ENTER
                    || geoNotification.lastTransitionType == Geofence.GEOFENCE_TRANSITION_DWELL)) {
                return true;
            }
        }
        return false;
    }

    private static void notifyNativeTransition(Context context, int transitionType,
                                               boolean hasActiveInsideGeofence) {
        try {
            Class<?> handlerClass = Class.forName(
                    "com.marianhello.bgloc.GeofenceTransitionHandler");
            Method handler = handlerClass.getMethod("onGeofenceTransition", Context.class,
                    Integer.TYPE, Boolean.TYPE);
            handler.invoke(null, context, transitionType, hasActiveInsideGeofence);
        } catch (ClassNotFoundException error) {
            // The geofence plugin can also be used without background geolocation.
        } catch (Exception error) {
            Logger.getLogger().log(Log.ERROR,
                    "Unable to notify native geofence transition: " + error.getMessage());
        }
    }

    private static void scheduleElapsedAlarm(Context context, String action,
                                             int requestCode, long delayMillis) {
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(
                Context.ALARM_SERVICE);
        if (alarmManager == null) {
            return;
        }
        PendingIntent pendingIntent = createPendingIntent(context, action, requestCode);
        long triggerAtMillis = SystemClock.elapsedRealtime() + delayMillis;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis, pendingIntent);
        } else {
            alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerAtMillis, pendingIntent);
        }
    }

    private static void scheduleWallClockAlarm(Context context, String action,
                                               int requestCode, long triggerAtMillis) {
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(
                Context.ALARM_SERVICE);
        if (alarmManager == null) {
            return;
        }
        PendingIntent pendingIntent = createPendingIntent(context, action, requestCode);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,
                    triggerAtMillis, pendingIntent);
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
        }
    }

    private static void cancelAlarm(Context context, String action, int requestCode) {
        AlarmManager alarmManager = (AlarmManager) context.getSystemService(
                Context.ALARM_SERVICE);
        if (alarmManager != null) {
            alarmManager.cancel(createPendingIntent(context, action, requestCode));
        }
    }

    private static PendingIntent createPendingIntent(Context context, String action,
                                                     int requestCode) {
        Intent intent = new Intent(context, GeofenceTrackingCoordinator.class);
        intent.setAction(action);
        return PendingIntent.getBroadcast(context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}