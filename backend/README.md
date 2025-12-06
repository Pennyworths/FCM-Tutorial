# Backend Lambda Functions

## Table of Contents

- [Quick Start](#quick-start)
- [API Endpoints](#api-endpoints)
- [Database Schema](#database-schema)
- [RDS Connection](#rds-connection)
- [Deployment](#deployment)
- [Expected Output](#expected-output)

---

## Quick Start
 
```bash
cd backend

# Step 1: Deploy all Lambda functions
make deploy

# Step 2: Initialize database schema (REQUIRED after first deployment)
make init-schema
```

> ⚠️ **Prerequisites:**
> - Infrastructure must be deployed first (`infra/`)
> - AWS CLI configured with appropriate credentials
> - Docker installed and running

> 🚨 **Important:** After the first deployment, you **MUST** run `init-schema` to create database tables. Without this step, all API calls will fail with database errors.

### Make Commands

| Command | Description |
|---------|-------------|
| `make deploy` | Build and push all images to ECR |
| `make init-schema` | Initialize database tables (required after first deploy) |
| `make build` | Build images locally (no push) |
| `make test` | Run all tests |
| `make clean` | Remove local Docker images |

> 💡 Run `make help` to see all available commands.

---

## API Endpoints

Base URL: `https://<api-gateway-id>.execute-api.<region>.amazonaws.com/dev`

### POST `/devices/register`

Register a device for push notifications.

**Request:**

```json
{
  "user_id": "user-123",
  "device_id": "device-abc",
  "fcm_token": "fcm-token-xyz...",
  "platform": "android"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `user_id` | string | ✅ | User identifier |
| `device_id` | string | ✅ | Device identifier (globally unique) |
| `fcm_token` | string | ✅ | Firebase Cloud Messaging token |
| `platform` | string | ✅ | `android` or `ios` |

**Response (200):**

```json
{
  "ok": true
}
```

**Error (409 Conflict):** Device already registered to another user.

---

### POST `/messages/send`

Send push notification to all devices of a user.

**Request:**

```json
{
  "user_id": "user-123",
  "title": "Hello",
  "body": "World",
  "data": {
    "type": "e2e_test",
    "nonce": "uuid-here"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `user_id` | string | ✅ | Target user identifier |
| `title` | string | ✅ | Notification title |
| `body` | string | ✅ | Notification body |
| `data` | object | ❌ | Custom data payload |

**Response (200):**

```json
{
  "ok": true,
  "sent_count": 2
}
```

> 💡 If `data.type == "e2e_test"` and `data.nonce` is present, a test run record is created.

---

### POST `/test/ack`

Acknowledge receipt of an E2E test message.

**Request:**

```json
{
  "nonce": "uuid-here"
}
```

**Response (200):**

```json
{
  "ok": true
}
```

**Error (404):** Test run not found or already acknowledged.

---

### GET `/test/status?nonce=<nonce>`

Query test run status.

**Response (200 - PENDING):**

```json
{
  "nonce": "uuid-here",
  "status": "PENDING"
}
```

**Response (200 - ACKED):**

```json
{
  "nonce": "uuid-here",
  "status": "ACKED",
  "acked_at": "2024-01-15T10:30:00Z"
}
```

**Error (404):** Test run not found.

---

## Database Schema

### `devices` table

Stores FCM device registration information.

```sql
CREATE TABLE IF NOT EXISTS devices (
  id          SERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  platform    TEXT NOT NULL,        -- 'android' or 'ios'
  fcm_token   TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);
```

### `test_runs` table

Tracks E2E test message delivery status.

```sql
CREATE TABLE IF NOT EXISTS test_runs (
  nonce       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  status      TEXT NOT NULL,        -- 'PENDING' or 'ACKED'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at    TIMESTAMPTZ
);
```

---

## RDS Connection

### Security Model

- RDS is deployed in **private subnets**
- Only **Lambda security group** can access RDS (port 5432)
- ❌ Cannot connect directly from local machine
- ✅ Lambda functions connect via environment variables

### Environment Variables

Lambda functions receive RDS connection info automatically:

| Variable | Description |
|----------|-------------|
| `RDS_HOST` | RDS endpoint hostname |
| `RDS_PORT` | RDS port (5432) |
| `RDS_DB_NAME` | Database name |
| `RDS_USERNAME` | Database username |
| `RDS_PASSWORD` | Database password |

### Connection Code Example

```go
connStr := fmt.Sprintf(
    "host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
    os.Getenv("RDS_HOST"),
    os.Getenv("RDS_PORT"),
    os.Getenv("RDS_USERNAME"),
    os.Getenv("RDS_PASSWORD"),
    os.Getenv("RDS_DB_NAME"),
)
db, err := sql.Open("postgres", connStr)
```

---

## Deployment

### Deployment Flow

```
Step 1: Check Prerequisites
  └── Read Terraform outputs from infra modules

Step 2: Build and Push Docker Images
  └── Build images for all Lambda functions
  └── Push to ECR repository

Step 3: Update Lambda Functions
  └── terraform apply in infra/Lambdas/

Step 4: Initialize Database Schema (REQUIRED)
  └── Invoke initSchema Lambda function
  └── Creates 'devices' and 'test_runs' tables
```

### Lambda Functions

| Function | Handler | Description |
|----------|---------|-------------|
| `register-device` | `RegisterDeviceHandler` | Device registration |
| `send-message` | `SendMessageHandler` | Send FCM notifications |
| `test-ack` | `TestAckHandler` | E2E test acknowledgment |
| `test-status` | `TestStatusHandler` | E2E test status query |
| `init-schema` | `InitSchemaHandler` | Database initialization |

---

## Expected Output

### Successful Deployment

```
===========================================
Backend Lambda Deployment
===========================================

Step 1/4: Checking prerequisites...
✓ ECR repository found
✓ RDS connection info available

Step 2/4: Building and pushing Docker images...
✓ register-device image pushed
✓ send-message image pushed
✓ test-ack image pushed
✓ test-status image pushed
✓ init-schema image pushed

Step 3/4: Updating Lambda functions...
✓ Lambda functions updated

Step 4/4: Initializing database schema...
✓ Schema initialized successfully

===========================================
Deployment Complete!
===========================================
```

### Verify Deployment

```bash
# Check CloudWatch Logs for initSchema
# Get Lambda name from Terraform output first:
LAMBDA_NAME=$(cd infra/Lambdas && terraform output -raw init_schema_function_name)
aws logs tail /aws/lambda/$$LAMBDA_NAME --since 5m

# Test register endpoint
curl -X POST https://<api-url>/dev/devices/register \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","device_id":"dev1","fcm_token":"token","platform":"android"}'
# Expected: {"ok":true}

# Test send message endpoint
curl -X POST https://<api-url>/dev/messages/send \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","title":"Hello","body":"World"}'
# Expected: {"ok":true,"sent_count":1}
```

> 💡 The remaining two endpoints (`/test/ack` and `/test/status`) are used for **E2E testing only**.
> See `test/README.md` for how to run E2E tests.
