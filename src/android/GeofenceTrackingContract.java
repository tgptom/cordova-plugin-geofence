package com.cowbell.cordova.geofence;

public final class GeofenceTrackingContract {
    private GeofenceTrackingContract() {}

    public static final String COMPANION_HANDLER_CLASS = "com.marianhello.bgloc.GeofenceTransitionHandler";
    public static final String COMPANION_HANDLER_METHOD = "onGeofenceTransition";

    public static final String IOS_TRANSITION_NOTIFICATION = "AppGeofenceTrackingTransition";
    public static final String PAYLOAD_TRANSITION_TYPE = "transitionType";
    public static final String PAYLOAD_HAS_ACTIVE_INSIDE_GEOFENCE = "hasActiveInsideGeofence";

    public static final int TRANSITION_ENTER = 1;
    public static final int TRANSITION_EXIT = 2;
    public static final int TRANSITION_DWELL = 4;
}
