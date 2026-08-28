package com.cowbell.cordova.geofence;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        Logger.setLogger(new Logger(GeofencePlugin.TAG, context, false));
        GeoNotificationStore store = new GeoNotificationStore(context);
        for (GeoNotification geoNotification : store.getAll()) {
            if (geoNotification != null) {
                geoNotification.lastTransitionType = 0;
                store.setGeoNotification(geoNotification);
            }
        }
        GeoNotificationManager manager = new GeoNotificationManager(context);
        manager.loadFromStorageAndInitializeGeofences();
    }
}