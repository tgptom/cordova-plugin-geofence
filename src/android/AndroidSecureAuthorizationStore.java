package com.cowbell.cordova.geofence;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import androidx.security.crypto.EncryptedSharedPreferences;
import androidx.security.crypto.MasterKey;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.Map;

class AndroidSecureAuthorizationStore {
    private static final String PREF_NAME = "geofence_authorization_secure";
    private static final String KEY_PREFIX = "auth:";

    private final SharedPreferences securePrefs;

    AndroidSecureAuthorizationStore(Context context) {
        SharedPreferences prefs = null;
        try {
            MasterKey masterKey = new MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build();
            prefs = EncryptedSharedPreferences.create(
                    context,
                    PREF_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            );
        } catch (GeneralSecurityException | IOException error) {
            Log.w(GeofencePlugin.TAG, "Secure auth store unavailable; authorization headers will not persist", error);
        }
        this.securePrefs = prefs;
    }

    void setAuthorization(String geofenceId, String authorization) {
        if (securePrefs == null || geofenceId == null || geofenceId.isEmpty()) {
            return;
        }
        String key = KEY_PREFIX + geofenceId;
        if (authorization == null || authorization.trim().isEmpty()) {
            securePrefs.edit().remove(key).apply();
        } else {
            securePrefs.edit().putString(key, authorization).apply();
        }
    }

    String getAuthorization(String geofenceId) {
        if (securePrefs == null || geofenceId == null || geofenceId.isEmpty()) {
            return null;
        }
        return securePrefs.getString(KEY_PREFIX + geofenceId, null);
    }

    void removeAuthorization(String geofenceId) {
        if (securePrefs == null || geofenceId == null || geofenceId.isEmpty()) {
            return;
        }
        securePrefs.edit().remove(KEY_PREFIX + geofenceId).apply();
    }

    void clear() {
        if (securePrefs == null) {
            return;
        }
        SharedPreferences.Editor editor = securePrefs.edit();
        for (Map.Entry<String, ?> entry : securePrefs.getAll().entrySet()) {
            if (entry.getKey().startsWith(KEY_PREFIX)) {
                editor.remove(entry.getKey());
            }
        }
        editor.apply();
    }
}
