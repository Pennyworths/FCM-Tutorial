# E2E Test

This directory contains end-to-end test scripts for the FCM push notification system.

## Available Implementations

Three implementations are available:

1. **Shell script** (`e2e_test.sh`) - Lightweight, uses curl
2. **Node.js** (`e2e_test.js`) - Uses Node.js built-in modules
3. **Python** (`e2e_test.py`) - Uses Python standard library

## Setup

### 1. Create `.env` file

Copy the following into `test/.env`:

```env
API_BASE_URL=https://xxxx.execute-api.region.amazonaws.com/prod
TEST_USER_ID=debug-user-2
TIMEOUT_SECONDS=30
```

### 2. Build and Run

#### Option A: Shell Script (Recommended - Lightweight)

```bash
docker build -f DockerFile -t fcm-e2e-test .
docker run --rm --env-file .env fcm-e2e-test
```

#### Option B: Node.js

```bash
docker build -f Dockerfile.nodejs -t fcm-e2e-test .
docker run --rm --env-file .env fcm-e2e-test
```

#### Option C: Python

```bash
docker build -f Dockerfile.python -t fcm-e2e-test .
docker run --rm --env-file .env fcm-e2e-test
```

## Test Flow

1. Load environment variables from `.env`
2. Generate a nonce (UUID)
3. Call `POST /messages/send` with test payload
4. Poll `GET /test/status?nonce={nonce}` every 2 seconds
5. Exit with code 0 if status becomes "ACKED" within timeout
6. Exit with code 2 if timeout is reached

## Exit Codes

- `0`: Success - Status became ACKED
- `1`: Error - Failed to send message or other error
- `2`: Timeout - Did not receive ACKED status within timeout period

