package com.cowbell.cordova.geofence;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.app.job.JobInfo;
import android.app.job.JobScheduler;
import android.content.ComponentName;
import android.content.Context;
import android.os.PersistableBundle;
import android.util.Log;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

import org.json.JSONObject;

/**
 * Created by jupe on 22-02-18.
 */

public class TransitionJobService extends JobService {
    static final String KEY_ATTEMPT = "attempt";
    static final String KEY_JOB_ID = "jobId";
    static final String KEY_ALLOW_INSECURE_HTTP = "allowInsecureHttp";
    static final int MAX_RETRY_ATTEMPTS = 3;
    static final long RETRY_BACKOFF_MS = 10000L;

    private Thread workerThread;
    private final AtomicBoolean isStopped = new AtomicBoolean(false);
    private final AtomicBoolean retryScheduled = new AtomicBoolean(false);

    @Override
    public boolean onStartJob(final JobParameters jobParameters) {
        PersistableBundle params = jobParameters.getExtras();
        final String url = params.getString("url");
        final String authorization = params.getString("authorization");
        final String id = params.getString("id");
        final String transition = params.getString("transition");
        final String date = params.getString("date");
        final int attempt = params.getInt(KEY_ATTEMPT, 0);
        final int jobId = params.getInt(KEY_JOB_ID, jobParameters.getJobId());
        final boolean allowInsecureHttp = params.getBoolean(KEY_ALLOW_INSECURE_HTTP, false);

        isStopped.set(false);
        retryScheduled.set(false);
        workerThread = new Thread(() -> {
            try {
                sendTransitionToServer(url, authorization, id, transition, date, allowInsecureHttp);
                jobFinished(jobParameters, false);
            } catch (Exception exception) {
                if (isStopped.get()) {
                    return;
                }
                Log.e(GeofencePlugin.TAG, "Error while sending geofence transition", exception);
                scheduleRetryIfPossible(params, attempt, jobId);
                jobFinished(jobParameters, false);
            }
        });
        workerThread.start();

        return true; // Async
    }

    @Override
    public boolean onStopJob(JobParameters jobParameters) {
        isStopped.set(true);
        Thread thread = workerThread;
        if (thread != null) {
            thread.interrupt();
        }
        PersistableBundle params = jobParameters.getExtras();
        int attempt = params.getInt(KEY_ATTEMPT, 0);
        int jobId = params.getInt(KEY_JOB_ID, jobParameters.getJobId());
        scheduleRetryIfPossible(params, attempt, jobId);
        return false;
    }

    private void sendTransitionToServer(
        String urlString,
        String authorization,
        String id,
        String transition,
        String date,
        boolean allowInsecureHttp
    ) throws Exception {
        URL url = validateCallbackUrl(urlString, allowInsecureHttp);
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) url.openConnection();
            conn.setReadTimeout(10000);
            conn.setConnectTimeout(15000);
            conn.setRequestMethod("POST");
            conn.setDoInput(true);
            conn.setDoOutput(true);

            if (authorization != null && !authorization.isEmpty()) {
                conn.setRequestProperty("Authorization", authorization);
            }
            conn.setRequestProperty("Content-Type", "application/json");

            JSONObject payload = new JSONObject();
            payload.put("geofenceId", id);
            payload.put("transition", transition);
            payload.put("date", date);

            try (OutputStream os = conn.getOutputStream();
                 BufferedWriter writer = new BufferedWriter(
                     new OutputStreamWriter(os, StandardCharsets.UTF_8))) {
                writer.write(payload.toString());
                writer.flush();
            }

            int responseCode = conn.getResponseCode();
            if (responseCode < 200 || responseCode >= 300) {
                throw new IOException("Webhook callback failed with HTTP status " + responseCode);
            }
            Log.i(GeofencePlugin.TAG, "Transition webhook delivered");
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    private URL validateCallbackUrl(String urlString, boolean allowInsecureHttp) throws Exception {
        if (urlString == null || urlString.trim().isEmpty()) {
            throw new MalformedURLException("Missing callback URL");
        }
        URL url = new URL(urlString);
        String protocol = url.getProtocol() == null ? "" : url.getProtocol().toLowerCase(Locale.US);
        if ("https".equals(protocol)) {
            return url;
        }
        if ("http".equals(protocol) && allowInsecureHttp) {
            return url;
        }
        if ("http".equals(protocol)) {
            throw new SecurityException("HTTP callback URLs are blocked by default. Set allowInsecureHttp=true only for development.");
        }
        throw new MalformedURLException("Unsupported callback URL scheme");
    }

    private void scheduleRetryIfPossible(PersistableBundle originalParams, int attempt, int jobId) {
        if (attempt >= MAX_RETRY_ATTEMPTS || !retryScheduled.compareAndSet(false, true)) {
            return;
        }
        JobScheduler jobScheduler = (JobScheduler) getSystemService(Context.JOB_SCHEDULER_SERVICE);
        if (jobScheduler == null) {
            return;
        }
        PersistableBundle retryParams = new PersistableBundle(originalParams);
        retryParams.putInt(KEY_ATTEMPT, attempt + 1);
        retryParams.putInt(KEY_JOB_ID, jobId);
        JobInfo retryJob = new JobInfo.Builder(jobId, new ComponentName(this, TransitionJobService.class))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setMinimumLatency(RETRY_BACKOFF_MS)
            .setBackoffCriteria(RETRY_BACKOFF_MS, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            .setExtras(retryParams)
            .build();
        jobScheduler.schedule(retryJob);
    }
}
