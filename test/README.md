# FCM E2E Test

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
- `user_id`: e.g., `debug-user-1`
- `device_id`: auto-generated UUID
- `FCM token`: Firebase token

Create `test/.env`:

```env
API_BASE_URL=https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev
TEST_USER_ID=debug-user-1
TIMEOUT_SECONDS=30
```

> ⚠️ `TEST_USER_ID` must match the `user_id` shown in the app.

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
[INFO] Using nonce = 550e8400-e29b-41d4-a716-446655440000
[INFO] POST https://xxx.execute-api.us-east-1.amazonaws.com/dev/messages/send
[DEBUG] Payload: {"user_id": "debug-user-1", ...}
[INFO] /messages/send HTTP 200, body={"ok":true,"sent_count":1}
[INFO] Start polling .../test/status?nonce=550e8400-... for up to 30s
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
| Timeout | Wrong `TEST_USER_ID` | Match the `user_id` shown in app |
| API error 404 | Backend not deployed | Run `make deploy` in `backend/` |
