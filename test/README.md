# FCM E2E Test

## How to Run

### 1. Create `.env` file

```env
API_BASE_URL=https://your-api-gateway-url.amazonaws.com/dev
TEST_USER_ID=debug-user-1
TIMEOUT_SECONDS=30
```

### 2. Run with Docker

```bash
cd test
docker build -t fcm-e2e-test .
docker run --env-file .env fcm-e2e-test
```

### 3. Prerequisites

- Android app must be **running in foreground**
- Device must be registered with backend

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | ✅ Test passed |
| `1` | ❌ Test failed |
| `2` | ⏱️ Timeout |

## Expected Output

### Success

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

### Timeout

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
