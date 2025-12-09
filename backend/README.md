# Backend Lambda Functions

## Table of Contents

- [Quick Start](#quick-start)
- [API Endpoints](#api-endpoints)
- [Database Schema](#database-schema)
- [RDS Connection](#rds-connection)
- [Deployment](#deployment)
- [Database Migrations](#database-migrations)
- [Expected Output](#expected-output)

---

## Quick Start
 
```bash
cd backend

# Step 1: Deploy all Lambda functions
make deploy

# Step 2: Run database migrations (REQUIRED after first deployment)
cd migrations

# Build Docker image (first time only)
make build

# Test database connection
make test

# Run migrations UP to create tables
make up

# Check migration status
make status

# List all database tables
make tables

# Query data from devices table
make query TABLE=devices

# Connect to database interactively (optional)
make connect
```

> ⚠️ **Prerequisites:**
> - Infrastructure must be deployed first (`infra/`)
> - AWS CLI configured with appropriate credentials
> - Docker installed and running

> 🚨 **Important:** After the first deployment, you **MUST** run database migrations to create database tables. Without this step, all API calls will fail with database errors.

### Make Commands

| Command | Description |
|---------|-------------|
| `make deploy` | Build and push all images to ECR |
| `make build` | Build images locally (no push) |
| `make test` | Run all tests |
| `make clean` | Remove local Docker images |

> 💡 Run `make help` to see all available commands.

### Database Migrations

Database migrations are managed in the `migrations/` directory. See [Database Migrations](#database-migrations) section below for details.

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

Step 4: Run Database Migrations (REQUIRED)
  └── cd migrations && make up
  └── Creates 'devices' and 'test_runs' tables
```

### Lambda Functions

| Function | Handler | Description |
|----------|---------|-------------|
| `register-device` | `RegisterDeviceHandler` | Device registration |
| `send-message` | `SendMessageHandler` | Send FCM notifications |
| `test-ack` | `TestAckHandler` | E2E test acknowledgment |
| `test-status` | `TestStatusHandler` | E2E test status query |

---

## Expected Output

### Successful Deployment

```
===========================================
Backend Lambda Deployment
===========================================

Step 1/3: Checking prerequisites...
✓ ECR repository found
✓ RDS connection info available

Step 2/3: Building and pushing Docker images...
✓ register-device image pushed
✓ send-message image pushed
✓ test-ack image pushed
✓ test-status image pushed

Step 3/3: Updating Lambda functions...
✓ Lambda functions updated

===========================================
Deployment Complete!
===========================================
```

### Verify Deployment

```bash
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

---

## Database Migrations

Database migrations are managed using Go migrate in the `migrations/` directory.

### Running Migrations

After deploying infrastructure, run migrations to create database tables:

```bash
cd migrations

# Step 1: Build Docker image (first time only)
make build

# Step 2: Test database connection
make test

# Step 3: Run migrations UP
make up
```

### Migration Commands

| Command | Description |
|---------|-------------|
| `make up` | Run database migrations UP |
| `make down` | Rollback migrations DOWN |
| `make status` | Check current migration version |
| `make test` | Test database connection |
| `make connect` | Connect to database interactively |
| `make tables` | List all database tables |
| `make query TABLE=devices` | Query data from a table |

### Viewing Database Tables

After running migrations, you can view the database tables:

```bash
cd migrations

# List all tables
make tables

# Query data from devices table
make query TABLE=devices

# Query data from test_runs table
make query TABLE=test_runs

# Query with limit
make query TABLE=devices LIMIT=10
```

### Interactive Database Access

For more complex queries, use interactive mode:

```bash
cd migrations
make connect
```

Then in the `psql` prompt:
```sql
-- List all tables
\dt

-- View devices table data
SELECT * FROM devices;

-- View test_runs table data
SELECT * FROM test_runs;

-- Count records
SELECT COUNT(*) FROM devices;
SELECT COUNT(*) FROM test_runs;
```

### Migration Files

Migration files are located in `migrations/migrate/`:
- `000001_initial_schema.up.sql` - Creates `devices` and `test_runs` tables
- `000001_initial_schema.down.sql` - Drops tables (rollback)

> 💡 See `migrations/README.md` for more details on the migration system.

> 💡 The remaining two endpoints (`/test/ack` and `/test/status`) are used for **E2E testing only**.
> See `test/README.md` for how to run E2E tests.
