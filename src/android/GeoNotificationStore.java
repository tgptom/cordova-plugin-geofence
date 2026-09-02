package com.cowbell.cordova.geofence;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;

public class GeoNotificationStore {
    private LocalStorage storage;
    private AndroidSecureAuthorizationStore authorizationStore;

    public GeoNotificationStore(Context context) {
        storage = new LocalStorage(context);
        authorizationStore = new AndroidSecureAuthorizationStore(context);
    }

    public void setGeoNotification(GeoNotification geoNotification) {
        if (geoNotification == null) {
            return;
        }
        authorizationStore.setAuthorization(geoNotification.id, geoNotification.authorization);
        geoNotification.authorization = null;
        storage.setItem(geoNotification.id, Gson.get().toJson(geoNotification));
    }

    public GeoNotification getGeoNotification(String id) {
        String objectJson = storage.getItem(id);
        GeoNotification geoNotification = GeoNotification.fromJson(objectJson);
        if (geoNotification != null) {
            geoNotification.authorization = authorizationStore.getAuthorization(geoNotification.id);
        }
        return geoNotification;
    }

    public List<GeoNotification> getAll() {
        List<String> objectJsonList = storage.getAllItems();
        List<GeoNotification> result = new ArrayList<GeoNotification>();
        for (String json : objectJsonList) {
            GeoNotification geoNotification = GeoNotification.fromJson(json);
            if (geoNotification != null) {
                geoNotification.authorization = authorizationStore.getAuthorization(geoNotification.id);
                result.add(geoNotification);
            }
        }
        return result;
    }

    public void remove(String id) {
        storage.removeItem(id);
        authorizationStore.removeAuthorization(id);
    }

    public void clear() {
        storage.clear();
        authorizationStore.clear();
    }
}
