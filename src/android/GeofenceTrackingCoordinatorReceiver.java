package com.cowbell.cordova.geofence;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class GeofenceTrackingCoordinatorReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Logger.setLogger(new Logger(GeofencePlugin.TAG, context, false));
        GeofenceTrackingCoordinator coordinator = new GeofenceTrackingCoordinator(context);
        coordinator.onAlarm(intent);
    }
}
