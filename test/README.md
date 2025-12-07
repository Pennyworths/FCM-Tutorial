# FCM Tests

This directory contains two types of tests:

1. **E2E Test** (`e2e_test.py`) - Full end-to-end test with FCM push notifications and Android app
2. **Integration Test** (`integration_test.py`) - Backend API and database integration test (no FCM/Android required)

---

## Integration Test

Integration test verifies the integration between:
- API Gateway endpoints
- Lambda functions  
- RDS PostgreSQL database

**It does NOT test FCM push notifications or Android app.**

### Prerequisites

- **Docker** - installed and running
- **AWS account** - with credentials configured
- **Backend deployed** - Infrastructure and Lambda functions must be deployed

### Run Integration Test

```bash
cd test

# Build Docker image
docker build -f Dockerfile.integration -t fcm-integration-test .

# Run test (only needs API_BASE_URL)
docker run --env-file .env fcm-integration-test
```

Or directly with Python:

```bash
cd test

# Set environment variable
export API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev

# Run test
python3 integration_test.py
```

### Integration Test Environment Variables

Create `test/.env` with:

```env
API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev
```

**Note:** Integration test only needs `API_BASE_URL`. It does NOT need `TEST_USER_ID` (test creates its own test users).

### Integration Test Expected Output

#### ✅ Success

```
==================================================
FCM API Integration Tests
==================================================
API Base URL: https://xxx.execute-api.us-east-1.amazonaws.com/dev

==================================================
Test Suite 1: Device Registration
==================================================

[TEST] Device Registration
==================================================
POST https://xxx.execute-api.us-east-1.amazonaws.com/dev/devices/register
Payload: {
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "device_id": "660e8400-e29b-41d4-a716-446655440001",
  "fcm_token": "test-fcm-token-...",
  "platform": "android"
}
Response: HTTP 200
Body: {"ok":true}
[PASS] Device registration successful

[TEST] Device Registration (Duplicate - Should Update)
==================================================
[PASS] Duplicate device registration successfully updated

[TEST] Device Registration (iOS Platform)
==================================================
[PASS] iOS device registration successful

[TEST] Device Registration (Invalid Platform)
==================================================
[PASS] Invalid platform correctly rejected

[TEST] Device Registration (Missing Fields)
==================================================
[PASS] Missing fields correctly rejected

==================================================
Test Suite 2: Send Message
==================================================

[TEST] Send Message
==================================================
[PASS] Message send correctly returned ok=false, sent_count=0 (no devices)

[TEST] Send Message (Create Test Run)
==================================================
[VERIFY] ✓ Test run confirmed created with status=PENDING

[TEST] Send Message (User Not Found)
==================================================
[PASS] Non-existent user correctly returned ok=false, sent_count=0

[TEST] Send Message (Missing Fields)
==================================================
[PASS] Missing fields correctly rejected

==================================================
Test Suite 3: Test Status
==================================================

[TEST] Test Status (Non-existent)
==================================================
[PASS] Test status correctly returned 404 for non-existent nonce

[TEST] Test Status (Valid Nonce)
==================================================
[PASS] Test status correctly returned PENDING

[TEST] Test Status (Missing Nonce)
==================================================
[PASS] Missing nonce parameter correctly rejected

==================================================
Test Suite 4: Test Acknowledgment
==================================================

[TEST] Test Ack (Valid)
==================================================
[PASS] Test ack successful

[TEST] Test Status (After Ack - Should be ACKED)
==================================================
[PASS] Test status correctly shows ACKED after acknowledgment

==================================================
Test Summary
==================================================
Passed: 13
Failed: 0
Total: 13
Success Rate: 100.0%

[SUCCESS] All integration tests passed!
```

#### ❌ Failure Example

```
==================================================
Test Suite 1: Device Registration
==================================================

[TEST] Device Registration
==================================================
POST https://xxx.execute-api.us-east-1.amazonaws.com/dev/devices/register
Response: HTTP 500
Body: {"error":"Database connection failed"}
[FAIL] Expected 200, got 500

==================================================
Test Summary
==================================================
Passed: 0
Failed: 1
Total: 1
Success Rate: 0.0%

[FAIL] Some tests failed
```

---

## E2E Test

End-to-end test for verifying FCM push notification delivery.

## Prerequisites

- **Docker** - installed and running
- **Android Studio** - to build and run the app
- **Android device/emulator** - to receive FCM notifications
- **AWS account** - with credentials configured
- **Firebase project** - with `google-services.json` configured

## Full Test Flow

### Step 1: Deploy Infrastructure + Backend

```bash
# 1.1 Deploy infrastructure
cd infra
make start              # Configure AWS credentials
make deploy-all         # Deploy all resources

# 1.2 Deploy backend
cd ../backend
make deploy             # Build and push Lambda images
make init-schema        # Initialize database
```

### Step 2: Install and Open the Android App

1. Open `android/` folder in Android Studio
2. Configure `android/local.properties`:
   ```properties
   API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev
   ```
   > Get this URL from `make output` in `infra/`

3. Run the app on your device/emulator
4. **Keep the app open in foreground**

### Step 3: Copy App Info to `.env`

The app displays:
- `user_id`: **auto-generated UUID** (e.g., `550e8400-e29b-41d4-a716-446655440000`)
- `device_id`: auto-generated UUID
- `FCM token`: Firebase token

**Important:** The app now generates a random UUID for `user_id` on first launch. This UUID is persisted and displayed in the app UI.

Create `test/.env`:

```env
API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev
TEST_USER_ID=550e8400-e29b-41d4-a716-446655440000
TIMEOUT_SECONDS=30
```

> ⚠️ **`TEST_USER_ID` must match the `user_id` shown in the Android app.**
> 
> 1. Open the Android app and check the `user_id` value displayed on screen
> 2. Copy that UUID and paste it as `TEST_USER_ID` in the `.env` file
> 3. The format should be: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

### Step 4: Run the Test

```bash
cd test

# Build Docker image
docker build -t fcm-e2e-test .

# Run test
docker run --env-file .env fcm-e2e-test
```

## Test Flow Diagram

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   E2E Test      │     │    Backend      │     │   Android App   │
│   (Docker)      │     │   (Lambda)      │     │   (Foreground)  │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │ POST /messages/send   │                       │
         │ (nonce=uuid)          │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │                       │  FCM Push (nonce)     │
         │                       │──────────────────────>│
         │                       │                       │
         │                       │  POST /test/ack       │
         │                       │<──────────────────────│
         │                       │                       │
         │ GET /test/status      │                       │
         │ (polling)             │                       │
         │──────────────────────>│                       │
         │                       │                       │
         │ {"status":"ACKED"}    │                       │
         │<──────────────────────│                       │
         │                       │                       │
         │ ✅ Test Passed!       │                       │
         │                       │                       │
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | ✅ Test passed - message delivered and acknowledged |
| `1` | ❌ Test failed - API error or unexpected response |
| `2` | ⏱️ Timeout - message not acknowledged within timeout |

## Expected Output

### ✅ Success

```
[INFO] Loading environment from /app/.env
[INFO] Test configuration:
[INFO]   API_BASE_URL = https://xxx.execute-api.us-east-1.amazonaws.com/dev
[INFO]   TEST_USER_ID = 550e8400-e29b-41d4-a716-446655440000
[INFO]   TIMEOUT_SECONDS = 30
[INFO] Using nonce = 7c9e6679-7425-40de-944b-e07fc1f90ae7
[INFO] POST https://xxx.execute-api.us-east-1.amazonaws.com/dev/messages/send
[DEBUG] Payload: {"user_id": "550e8400-e29b-41d4-a716-446655440000", ...}
[INFO] /messages/send HTTP 200, body={"ok":true,"sent_count":1}
[INFO] Start polling .../test/status?nonce=7c9e6679-... for up to 30s
[DEBUG] GET .../test/status?nonce=... -> HTTP 200, body={"status":"PENDING",...}
[DEBUG] GET .../test/status?nonce=... -> HTTP 200, body={"status":"ACKED",...}
[SUCCESS] Status became ACKED 🎉
```

### ⏱️ Timeout

```
[INFO] Loading environment from /app/.env
[INFO] Using nonce = 550e8400-e29b-41d4-a716-446655440000
[INFO] POST https://xxx.execute-api.us-east-1.amazonaws.com/dev/messages/send
[INFO] /messages/send HTTP 200, body={"ok":true,"sent_count":1}
[INFO] Start polling .../test/status?nonce=550e8400-... for up to 30s
[DEBUG] GET .../test/status?nonce=... -> HTTP 200, body={"status":"PENDING",...}
... (polling continues)
[ERROR] TIMEOUT waiting for status=ACKED
```

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `sent_count: 0` | No device registered | Open app, wait for registration, check logs |
| Timeout | App not in foreground | Keep app open and visible |
| Timeout | Wrong `TEST_USER_ID` | Copy the UUID `user_id` shown in app (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) |
| API error 404 | Backend not deployed | Run `make deploy` in `backend/` |
