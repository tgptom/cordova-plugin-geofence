package com.cowbell.cordova.geofence;

import android.content.Context;
import android.util.Log;

import java.lang.reflect.Method;

public final class CompanionGeofenceBridge {
    private static Method cachedMethod;
    private static boolean didLogMissingClass;
    private static boolean didLogIncompatibleMethod;

    private CompanionGeofenceBridge() {}

    public static synchronized void notifyTransition(Context context, int transitionType,
                                                     boolean hasActiveInsideGeofence) {
        Method method = resolveMethod();
        if (method == null) {
            return;
        }

        try {
            method.invoke(null, context.getApplicationContext(), transitionType, hasActiveInsideGeofence);
        } catch (Exception error) {
            Logger logger = Logger.getLogger();
            if (logger != null) {
                logger.log(Log.WARN, "Companion geolocation integration failed: " + error.getMessage());
            } else {
                Log.w(GeofencePlugin.TAG, "Companion geolocation integration failed", error);
            }
        }
    }

    private static Method resolveMethod() {
        if (cachedMethod != null) {
            return cachedMethod;
        }

        Logger logger = Logger.getLogger();

        try {
            Class<?> handlerClass = Class.forName(GeofenceTrackingContract.COMPANION_HANDLER_CLASS);
            cachedMethod = handlerClass.getMethod(
                    GeofenceTrackingContract.COMPANION_HANDLER_METHOD,
                    Context.class,
                    int.class,
                    boolean.class
            );
            return cachedMethod;
        } catch (ClassNotFoundException error) {
            if (!didLogMissingClass) {
                didLogMissingClass = true;
                if (logger != null) {
                    logger.log(Log.DEBUG, "Companion plugin not installed. Continuing standalone geofence mode.");
                } else {
                    Log.d(GeofencePlugin.TAG, "Companion plugin not installed. Continuing standalone geofence mode.");
                }
            }
        } catch (NoSuchMethodException error) {
            if (!didLogIncompatibleMethod) {
                didLogIncompatibleMethod = true;
                if (logger != null) {
                    logger.log(Log.WARN, "Companion plugin version is incompatible with geofence transition bridge.");
                } else {
                    Log.w(GeofencePlugin.TAG, "Companion plugin version is incompatible with geofence transition bridge.");
                }
            }
        }

        return null;
    }
}
