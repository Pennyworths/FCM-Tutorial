# FCM-Tutorial

## 1. Project Goal

Build a minimal but realistic FCM push demo with:

- Native Android app (Kotlin) + Firebase FCM
- AWS backend (API Gateway + Lambda + RDS + Secrets Manager) managed by Terraform
- End-to-end test running inside Docker

### Flow

1. Deploy infra + backend.
2. Install and open Android app (it auto-registers FCM and shows info).
3. Copy values from the app into a .env file for the test.
4. Run the e2e test in Docker:
   backend sends a push → app receives it → app calls back an API → test verifies success.

> Android only. No iOS.

---

## 2. Repository Layout

```text
repo-root/
  infra/      # Terraform: VPC, RDS, Lambdas, API Gateway, Secrets
  backend/    # Lambda source code
  android/    # Native Android app (Kotlin)
  test/       # e2e test script + Dockerfile + .env.example
```

---

## 3. Infra (Terraform)

All infra lives in infra/, using Terraform.

Create:

- VPC
  - One public + one private subnet is enough.
- RDS (Postgres)
  - In private subnet.
  - Security group: only Lambda can access.
- API Gateway (REST API)
- Lambda functions:
  - registerDeviceHandler
  - sendMessageHandler
  - testAckHandler
  - testStatusHandler
- IAM Role for Lambdas:
  - Can access RDS (via VPC).
  - Can read FCM credentials from Secrets Manager.
- Secrets Manager:
  - Store FCM service account JSON (or config needed to get an access token).

Terraform must output at least:

- api_base_url (API Gateway base URL)
- RDS host / port / db name (no password in outputs)

---

## 4. Database Schema (RDS Postgres)

Create two tables.

### 4.1 devices table

```sql
CREATE TABLE devices (
  id          SERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  platform    TEXT NOT NULL, -- 'android'
  fcm_token   TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);
```

Behavior:

- Upsert by (user_id, device_id):
  - If exists: update fcm_token, is_active = TRUE, updated_at = NOW()
  - If not: insert a new row.

### 4.2 test_runs table

```sql
CREATE TABLE test_runs (
  nonce       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  status      TEXT NOT NULL, -- 'PENDING' or 'ACKED'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at    TIMESTAMPTZ
);
```

---

## 5. Backend APIs

All APIs are JSON over HTTP, via API Gateway + Lambda.

### 5.1 POST /devices/register

Request:

```json
{
  "user_id": "string",
  "device_id": "string",
  "fcm_token": "string",
  "platform": "android"
}
```

Rules:

- Validate required fields.
- platform must be "android".
- Upsert into devices by (user_id, device_id) as described above.

Response:

```json
{ "ok": true }
```

(Currently user_id is passed from the client; code should be structured so that in the future it can come from an auth system like Cognito instead.)

---

### 5.2 POST /messages/send

Used for both normal and e2e test messages.

Request:

```json
{
  "user_id": "string",
  "title": "string",
  "body": "string",
  "data": {
    "any": "optional"
  }
}
```

- Query devices for all rows where user_id = ? and is_active = TRUE and platform = 'android'.
- Use FCM HTTP v1 API to send the notification to each fcm_token, using the credentials stored in Secrets Manager.
- If data.type == "e2e_test" and data.nonce is present:
  - Insert a row into test_runs with:
  - nonce, user_id, status = 'PENDING'.

Response:

```json
{
  "ok": true,
  "sent_count": 1
}
```

(If multiple devices are active, sent_count may be > 1.)

---

### 5.3 POST /test/ack

Called by the app after receiving an e2e test push.

Request:

```json
{
  "nonce": "uuid-string"
}
```

Behavior:

- Look up test_runs.nonce:
  - If not found: return 404.
  - If found: set status = 'ACKED', acked_at = NOW().

Response:

```json
{ "ok": true }
```

---

### 5.4 GET /test/status

Used by the e2e test script.

Response examples:

```json
{
  "nonce": "uuid-string",
  "status": "PENDING"
}
```

or

```json
{
  "nonce": "uuid-string",
  "status": "ACKED",
  "acked_at": "2025-11-23T12:34:56Z"
}
```

---

## 6. Android Native App (Kotlin)

### 6.1 Tech

- Native Android app, Kotlin.
- Example package name: com.example.fcmplayground.
- Integrate Firebase:
  - Add google-services.json under app/.
  - Add Firebase Messaging dependency.

### 6.2 Behavior

1. On first launch
   - Initialize Firebase.
   - Request notification permission (for Android 13+).
   - Generate a persistent device_id (UUID stored in SharedPreferences).
   - Use a fixed test user_id (e.g., "debug-user-1").
2. Token handling
   - Get FCM token on startup.
   - Display on screen:
     - user_id
     - device_id
     - fcm_token
     - API base URL (this can be configured in the app or via build config).
   - Automatically call POST /devices/register when a token is obtained.
   - Listen for token refresh and re-call /devices/register.
3. UI
   - A single Activity is enough:
     - Text fields showing user_id, device_id, fcm_token, API_BASE_URL.
     - A "Re-register device" button that triggers /devices/register again.
4. Receiving messages
   - Implement FirebaseMessagingService:
     - On message:
       - Read remoteMessage.data.
       - If data.type == "e2e_test":
         - Read data.nonce.
         - Call POST /test/ack with that nonce.
       - For other messages:
         - Show a standard notification using title and body.

---

## 7. e2e Test (Docker)

All tests run from inside Docker in the test/ directory.

### 7.1 .env file

Before running tests:

- Start the app on a device.
- Confirm the app shows:
  - user_id
  - device_id
  - fcm_token (for debugging)
  - API_BASE_URL
- Copy at least the following into test/.env:

```env
API_BASE_URL=https://xxxx.execute-api.region.amazonaws.com/prod
TEST_USER_ID=debug-user-1
TIMEOUT_SECONDS=30
```

Add other variables if needed.

### 7.2 Docker setup

In test/:

- Dockerfile:
  - Installs runtime (Node.js or Python).
  - Copies test script and .env (or mounts at runtime).
  - Sets the test script as the entrypoint.

### 7.3 Test script flow

Inside the container:

1. Load .env
2. Generate a nonce (UUID)
3. Call POST /messages/send with:

   ```json
   {
     "user_id": "debug-user-1",
     "title": "FCM E2E Test",
     "body": "Test message",
     "data": {
       "type": "e2e_test",
       "nonce": "uuid-string"
     }
   }
   ```

4. Poll GET /test/status?nonce={nonce} every 2 seconds, up to TIMEOUT_SECONDS
5. If status becomes "ACKED" within timeout:
   - Print SUCCESS and exit with code 0
6. Otherwise:
   - Print TIMEOUT and exit with non-zero code

---

## 8. Deliverables

The intern must provide:

- infra/
  - Terraform configs + README.md:
    - Required variables.
    - How to run terraform init/plan/apply.
- backend/
  - Lambda code.
  - Build/deploy instructions.
- android/
  - Kotlin source.
  - Short setup guide for Firebase + how to run the app.
- test/
  - Dockerfile
  - Test script
  - .env.example
  - README.md describing the full test flow:
    1. Deploy infra + backend
    2. Install and open the app
    3. Copy app-shown info into .env
    4. Run the test in Docker and interpret the result
