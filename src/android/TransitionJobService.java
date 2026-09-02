package com.cowbell.cordova.geofence;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.PersistableBundle;
import android.util.Log;

import java.io.BufferedWriter;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

import org.json.JSONObject;

/**
 * Created by jupe on 22-02-18.
 */

public class TransitionJobService extends JobService {
    private static final String META_ALLOW_INSECURE_CALLBACK_URLS =
            "com.cowbell.cordova.geofence.ALLOW_INSECURE_CALLBACK_URLS";
    private static final String META_CALLBACK_URL_ALLOWLIST =
            "com.cowbell.cordova.geofence.CALLBACK_URL_ALLOWLIST";

    @Override
    public boolean onStartJob(final JobParameters jobParameters) {
        PersistableBundle params = jobParameters.getExtras();
        final String url = params.getString("url");
        final String authorization = params.getString("authorization");
        final String id = params.getString("id");
        final String transition = params.getString("transition");
        final String date = params.getString("date");

        Thread thread = new Thread(() -> {
            try {
                if (!isAllowedCallbackUrl(this, url)) {
                    Log.w(GeofencePlugin.TAG, "Skipping transition callback to disallowed URL: " + url);
                    jobFinished(jobParameters, false);
                    return;
                }
                sendTransitionToServer(url, authorization, id, transition, date);
                jobFinished(jobParameters, false);
            } catch (Exception exception) {
                // It is possible to have no network during transition from Cellular to Wifi
                Log.e(GeofencePlugin.TAG, "Error while sending geofence transition, rescheduling", exception);
                jobFinished(jobParameters, true);
            }
        });
        thread.start();

        return true; // Async
    }

    @Override
    public boolean onStopJob(JobParameters jobParameters) {
        return false;
    }

    static boolean isAllowedCallbackUrl(Context context, String urlString) {
        if (urlString == null || urlString.trim().isEmpty()) {
            return false;
        }

        Uri uri = Uri.parse(urlString);
        String scheme = uri.getScheme();
        String host = uri.getHost();
        if (scheme == null || host == null || host.trim().isEmpty()) {
            return false;
        }

        boolean allowInsecure = readBooleanMetaData(context, META_ALLOW_INSECURE_CALLBACK_URLS, false);
        String normalizedScheme = scheme.toLowerCase(Locale.US);
        if (!allowInsecure && !"https".equals(normalizedScheme)) {
            return false;
        }
        if (allowInsecure && !"https".equals(normalizedScheme) && !"http".equals(normalizedScheme)) {
            return false;
        }

        Set<String> allowlist = readHostAllowlist(context);
        if (allowlist.isEmpty()) {
            return true;
        }

        String normalizedHost = host.toLowerCase(Locale.US);
        for (String allowedHost : allowlist) {
            if (normalizedHost.equals(allowedHost) || normalizedHost.endsWith("." + allowedHost)) {
                return true;
            }
        }
        return false;
    }

    private static boolean readBooleanMetaData(Context context, String key, boolean fallback) {
        try {
            ApplicationInfo appInfo = context.getPackageManager().getApplicationInfo(
                    context.getPackageName(),
                    PackageManager.GET_META_DATA
            );
            if (appInfo.metaData != null && appInfo.metaData.containsKey(key)) {
                return appInfo.metaData.getBoolean(key, fallback);
            }
        } catch (Exception ignored) {
        }
        return fallback;
    }

    private static Set<String> readHostAllowlist(Context context) {
        Set<String> result = new HashSet<String>();
        try {
            ApplicationInfo appInfo = context.getPackageManager().getApplicationInfo(
                    context.getPackageName(),
                    PackageManager.GET_META_DATA
            );
            if (appInfo.metaData == null) {
                return result;
            }
            String raw = appInfo.metaData.getString(META_CALLBACK_URL_ALLOWLIST);
            if (raw == null || raw.trim().isEmpty()) {
                return result;
            }
            String[] hosts = raw.split(",");
            for (String host : Arrays.asList(hosts)) {
                String normalized = host.trim().toLowerCase(Locale.US);
                if (!normalized.isEmpty()) {
                    result.add(normalized);
                }
            }
        } catch (Exception ignored) {
        }
        return result;
    }

    private void sendTransitionToServer(String urlString, String authorization, String id, String transition, String date) throws Exception {
        URL url = new URL(urlString);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setReadTimeout(10000);
        conn.setConnectTimeout(15000);
        conn.setRequestMethod("POST");
        conn.setDoInput(true);
        conn.setDoOutput(true);

        if (authorization != null) {
            conn.setRequestProperty("Authorization", authorization);
        }
        conn.setRequestProperty("Content-Type", "application/json");

        OutputStream os = conn.getOutputStream();
        BufferedWriter writer = new BufferedWriter(
                new OutputStreamWriter(os, "UTF-8"));
        JSONObject payload = new JSONObject();
        payload.put("geofenceId", id);
        payload.put("transition", transition);
        payload.put("date", date);
        String json = payload.toString();
        Log.i(GeofencePlugin.TAG, "Sending Geofence transition to server: " + json);
        writer.write(json);
        writer.flush();
        writer.close();
        os.close();

        conn.connect();
        int responseCode = conn.getResponseCode();
        Log.i(GeofencePlugin.TAG, "Send Geofence transition to server: " + responseCode);
    }
}
