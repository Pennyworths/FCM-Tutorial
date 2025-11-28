# Backend Lambda Functions

## How to Connect to RDS

### Infrastructure Resources for RDS Connection

The following resources are created in `infra/` to enable Lambda functions to connect to RDS:

**1. Lambda Security Group** (`infra/VPC/main.tf`)
- **Resource:** `aws_security_group.lambda`
- **Name:** `${environment}-lambda-sg` (e.g., `dev-lambda-sg`)
- **Purpose:** Security group assigned to all Lambda functions
- **Configuration:**
  - Allows all outbound traffic (needed for Lambda to access RDS and other AWS services)
  - Used as source security group in RDS security group ingress rules

**2. RDS Security Group** (`infra/RDS/main.tf`)
- **Resource:** `aws_security_group.rds`
- **Name:** `${environment}-rds-sg` (e.g., `dev-rds-sg`)
- **Purpose:** Security group for RDS instance
- **Configuration:**
  - **Ingress Rule:** Allows PostgreSQL traffic (port 5432) **only from Lambda security group**
  - This implements the requirement: "Security group: only Lambda can access"

**3. initSchema Lambda Function** (`infra/Lambdas/main.tf`)
- **Resource:** `aws_lambda_function.init_schema`
- **Function Name:** `${environment}-initSchema` (e.g., `dev-initSchema`)
- **Purpose:** Lambda function that connects to RDS and initializes database schema
- **Configuration:**
  - Package type: Docker container image
  - Image URI: `${ecr_repository_url}:init-schema-${image_tag}`
  - VPC configuration: Deployed in private subnets with Lambda security group
  - Environment variables: RDS connection info (RDS_HOST, RDS_PORT, RDS_DB_NAME, RDS_USERNAME, RDS_PASSWORD)
  - Timeout: 60 seconds (longer timeout for schema initialization)
  - Memory: 256 MB

**4. Lambda Invocation for Schema Initialization** (`infra/RDS/main.tf`)
- **Resource:** `aws_lambda_invocation.init_schema`
- **Purpose:** Automatically triggers `initSchema` Lambda after RDS is created
- **Configuration:**
  - Triggers when RDS endpoint changes or SQL schema file changes
  - Depends on RDS instance being available
  - Optional: Only created if `init_schema_lambda_name` variable is provided

**How they work together:**
1. Lambda functions (including `initSchema`) are assigned the Lambda security group
2. RDS security group allows ingress from Lambda security group on port 5432
3. `initSchema` Lambda connects to RDS using environment variables
4. `aws_lambda_invocation` automatically triggers schema initialization after RDS is ready
5. This creates a secure, automated path: RDS creation → Lambda invocation → Schema initialization

### Security Constraints

RDS is deployed in a **private subnet** with security group rules restricting access to: **only Lambda security group can access** (port 5432).

This means:
- ❌ Cannot connect directly from local machine
- ✅ Can only connect via Lambda functions (complies with security requirements)

### Connection Method: Via Lambda Functions

Lambda functions automatically connect to RDS through environment variables.

**How it works:**
- Lambda functions are deployed in the same VPC as RDS
- Lambda security group can access RDS security group (port 5432)
- RDS connection information is passed to Lambda via environment variables:
  - `RDS_HOST` - RDS endpoint hostname
  - `RDS_PORT` - RDS port (5432)
  - `RDS_DB_NAME` - Database name (fcmdb)
  - `RDS_USERNAME` - Database username
  - `RDS_PASSWORD` - Database password

**Implementation in Lambda code:**
```go
// Read RDS connection info from environment variables
rdsHost := os.Getenv("RDS_HOST")
rdsPort := os.Getenv("RDS_PORT")
rdsDBName := os.Getenv("RDS_DB_NAME")
rdsUsername := os.Getenv("RDS_USERNAME")
rdsPassword := os.Getenv("RDS_PASSWORD")

// Build PostgreSQL connection string
connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
    rdsHost, rdsPort, rdsUsername, rdsPassword, rdsDBName)

// Connect to database
db, err := sql.Open("postgres", connStr)
if err != nil {
    return fmt.Errorf("failed to connect to database: %w", err)
}
defer db.Close()

// Test connection
if err := db.Ping(); err != nil {
    return fmt.Errorf("failed to ping database: %w", err)
}
```

**Environment Variable Configuration:**
Environment variables are automatically set by Terraform when deploying Lambda (see `infra/Lambdas/main.tf`).

**Advantages:**
- ✅ Complies with security requirements ("only Lambda can access")
- ✅ No security group modifications needed
- ✅ Uses SSL encrypted connection (`sslmode=require`)
- ✅ Automated configuration, no manual operations required

---

## How to Run the Schema Init Script

The database schema is defined in `Schema/init.sql` and creates two tables for storing FCM-related data.

### Database Table Structure

**1. `devices` table**

Stores FCM device registration information.

```sql
CREATE TABLE IF NOT EXISTS devices (
  id          SERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  device_id   TEXT NOT NULL,
  platform    TEXT NOT NULL,        -- 'android'
  fcm_token   TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_id)
);
```

**Field Descriptions:**
- `id` - Auto-incrementing primary key
- `user_id` - User identifier
- `device_id` - Device identifier
- `platform` - Platform type (currently only 'android' is supported)
- `fcm_token` - Firebase Cloud Messaging token
- `is_active` - Whether device is active (default: TRUE)
- `updated_at` - Last update timestamp
- `UNIQUE (user_id, device_id)` - Unique constraint ensuring only one record per user per device

**Code Implementation for Connecting to Database and Creating Tables (`init-schema/main.go`):**
```go
// Read RDS connection info from environment variables
rdsHost := os.Getenv("RDS_HOST")
rdsPort := os.Getenv("RDS_PORT")
rdsDBName := os.Getenv("RDS_DB_NAME")
rdsUsername := os.Getenv("RDS_USERNAME")
rdsPassword := os.Getenv("RDS_PASSWORD")

// Build PostgreSQL connection string
connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
    rdsHost, rdsPort, rdsUsername, rdsPassword, rdsDBName)

// Connect to database
db, err := sql.Open("postgres", connStr)
if err != nil {
    return fmt.Errorf("failed to connect to database: %w", err)
}
defer db.Close()

// Test connection
if err := db.Ping(); err != nil {
    return fmt.Errorf("failed to ping database: %w", err)
}

// Read SQL schema file
sqlScriptPath := "/var/task/init.sql"
sqlScriptBytes, err := os.ReadFile(sqlScriptPath)
if err != nil {
    return fmt.Errorf("failed to read SQL script: %w", err)
}
sqlScript := string(sqlScriptBytes)

// Execute SQL statements in a transaction
tx, err := db.Begin()
if err != nil {
    return fmt.Errorf("failed to begin transaction: %w", err)
}
defer tx.Rollback()

// Split SQL script and execute each statement
statements := strings.Split(sqlScript, ";")
for _, stmt := range statements {
    stmt = strings.TrimSpace(stmt)
    if stmt == "" {
        continue
    }
    // Execute statement (including CREATE TABLE for devices)
    if _, err := tx.Exec(stmt); err != nil {
        return fmt.Errorf("failed to execute SQL: %w\nStatement: %s", err, stmt)
    }
}

// Commit transaction
if err := tx.Commit(); err != nil {
    return fmt.Errorf("failed to commit transaction: %w", err)
}
```

**2. `test_runs` table**

Tracks FCM message delivery status for end-to-end testing.

```sql
CREATE TABLE IF NOT EXISTS test_runs (
  nonce       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  status      TEXT NOT NULL,        -- 'PENDING' or 'ACKED'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acked_at    TIMESTAMPTZ
);
```

**Field Descriptions:**
- `nonce` - Unique test identifier (primary key)
- `user_id` - User identifier
- `status` - Test status ('PENDING' or 'ACKED')
- `created_at` - Creation timestamp
- `acked_at` - Acknowledgment timestamp (nullable)

**Verify Table Creation (`init-schema/main.go`):**
```go
// Verify tables were created successfully
var tableCount int
if err := db.QueryRow(`
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name IN ('devices', 'test_runs')
`).Scan(&tableCount); err != nil {
    return fmt.Errorf("failed to verify tables: %w", err)
}

if tableCount != 2 {
    return fmt.Errorf("expected 2 tables in public schema, but found %d", tableCount)
}
```

### Automatic Initialization (Recommended)

The schema is **automatically initialized** when deploying Lambda functions using `backend/deploy.sh`.

**How it works:**
1. `deploy.sh` deploys all Lambda functions (including `initSchema`)
2. If RDS is available, `deploy.sh` automatically triggers `initSchema` Lambda
3. `initSchema` Lambda performs the following operations:
   - Connects to RDS using environment variables (as described above)
   - Reads SQL script from `/var/task/init.sql` (copied during Docker build)
   - Executes SQL statements in a transaction
   - Verifies tables were created successfully

**Usage:**
```bash
cd backend
./deploy.sh
```

**Execution Flow:**
```
Step 1: Check Prerequisites
  - Read Terraform outputs from infra modules
  - Get RDS connection information

Step 2: Build and Push Docker Images
  - Build Docker images for all Lambda functions

Step 3: Update Lambda Functions
  - Update Lambda functions with latest images
  - Configure RDS environment variables

Step 4: Initialize Database Schema
  - Wait 10 seconds for environment variables to propagate
  - Invoke initSchema Lambda function
  - Retry up to 3 times if connection errors occur
  - Verify schema initialization via CloudWatch Logs
```

**Prerequisites:**
- RDS must be deployed and available
- `initSchema` Lambda function must be deployed
- Lambda must have correct RDS environment variables configured

### Schema Script Details

The `initSchema` Lambda function:
- Reads SQL from `/var/task/init.sql` (copied from `backend/Schema/init.sql` during Docker build)
- Executes statements in a transaction to ensure atomicity
- Uses `CREATE TABLE IF NOT EXISTS` (safe to run multiple times)
- Verifies table creation by checking `information_schema.tables`

**SQL Script Location:**
- Source code: `backend/Schema/init.sql`
- In Lambda container: `/var/task/init.sql`

### Verification

After schema initialization, verify tables were created:
```bash
# Check CloudWatch Logs
aws logs tail /aws/lambda/dev-initSchema --since 5m
```
If successful, the logs should show that tables were created.

---

## Deployment Strategy

The `backend/deploy.sh` script automates the deployment of Lambda functions. Here's how it works:

### Deployment Flow

**Step 1: Check Prerequisites**
- Reads Terraform outputs from `infra/` modules to get:
  - ECR repository URL (from `infra/Lambdas`)
  - VPC information (from `infra/VPC`)
  - RDS connection information (from `infra/RDS`)
  - Secrets Manager ARN (from `infra/Secrets`)
- Validates that required infrastructure is deployed
- Uses placeholder values if RDS is not yet available

**Step 2: Build and Push Docker Images**
- Calls `build-and-push-images.sh` to:
  - Compile Go code for each Lambda function
  - Build Docker images using `Lambda/Dockerfile`
  - Push images to ECR repository
- Builds images for: `register-device`, `send-message`, `test-ack`, `test-status`, `init-schema`

**Step 3: Update Lambda Functions**
- Runs `terraform apply` in `infra/Lambdas/` to:
  - Create/update Lambda functions with latest Docker images
  - Configure environment variables (RDS connection, Secrets Manager ARN)
  - Set up VPC configuration (subnets, security groups)
- Uses real RDS values if available, otherwise uses placeholders

**Step 4: Initialize Database Schema** (if RDS is available)
- Automatically triggers `initSchema` Lambda function
- Waits for environment variables to propagate (10 seconds)
- Retries up to 3 times if connection errors occur
- Verifies schema initialization via CloudWatch Logs

### Key Design Decisions

1. **Separation of Concerns:**
   - Infrastructure (VPC, RDS, Secrets) is deployed separately via `terraform apply` in each `infra/` module
   - Lambda functions are deployed via `backend/deploy.sh` which handles Docker image building and Lambda updates

2. **Flexible RDS Connection:**
   - Script works even if RDS is not yet deployed (uses placeholder values)
   - Can be re-run after RDS is available to update Lambda functions with real connection info
   - Automatically initializes schema when RDS becomes available

3. **Automated Schema Initialization:**
   - Schema initialization is triggered automatically by `deploy.sh`
   - Uses retry logic to handle transient connection issues
   - Verifies success via CloudWatch Logs

4. **Docker Image Management:**
   - All Lambda functions use the same generic `Dockerfile`
   - Images are tagged and pushed to ECR before Lambda functions are updated
   - Ensures Lambda functions always use the latest code

### Usage

```bash
cd backend
./deploy.sh
```

**Prerequisites:**
- Infrastructure must be deployed (at minimum: `infra/Lambdas` for ECR repository)
- AWS CLI configured with appropriate credentials
- Docker installed and running
