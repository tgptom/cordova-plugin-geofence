const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const servicePath = path.join(repoRoot, 'src/android/TransitionJobService.java');
const receiverPath = path.join(repoRoot, 'src/android/ReceiveTransitionsReceiver.java');

const serviceSource = fs.readFileSync(servicePath, 'utf8');
const receiverSource = fs.readFileSync(receiverPath, 'utf8');

assert(
  serviceSource.includes('JSONObject payload = new JSONObject();'),
  'Webhook payload must be serialized with JSONObject'
);

assert(
  serviceSource.includes('validateCallbackUrl(urlString, allowInsecureHttp)'),
  'Webhook sender must validate callback URL before opening a connection'
);

assert(
  serviceSource.includes('if (responseCode < 200 || responseCode >= 300)'),
  'Non-2xx webhook responses must be treated as failures'
);

assert(
  serviceSource.includes('conn.disconnect();'),
  'HttpURLConnection must be disconnected in finally'
);

assert(
  serviceSource.includes('MAX_RETRY_ATTEMPTS = 3'),
  'Webhook delivery retries must be bounded'
);

assert(
  serviceSource.includes('HTTP callback URLs are blocked by default'),
  'HTTP callbacks must require explicit opt-in'
);

assert(
  receiverSource.includes('bundle.putInt(TransitionJobService.KEY_JOB_ID, jobId);'),
  'Each webhook job must carry a dedicated JobScheduler ID'
);

assert(
  receiverSource.includes('private int nextWebhookJobId(Context context)'),
  'Receiver must generate unique job IDs instead of reusing a constant ID'
);

assert(
  !receiverSource.includes('new JobInfo.Builder(1,'),
  'Receiver must not use a constant JobScheduler ID that replaces pending transitions'
);

assert(
  !serviceSource.includes('Sending Geofence transition to server: '),
  'Webhook implementation must not log sensitive transition payloads'
);
