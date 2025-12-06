# Database Schema Initialization

This directory contains the SQL schema definition for the FCM Tutorial database.

## Files

- `init.sql` - SQL script defining the database schema (devices and test_runs tables)

## Schema Overview

### devices table
Stores FCM device registrations with the following fields:
- `id` - Auto-incrementing primary key
- `user_id` - User identifier (TEXT)
- `device_id` - Device identifier (TEXT)
- `platform` - Platform type (TEXT, e.g., 'android')
- `fcm_token` - Firebase Cloud Messaging token (TEXT)
- `is_active` - Active status flag (BOOLEAN, default: TRUE)
- `updated_at` - Last update timestamp (TIMESTAMPTZ)
- Unique constraint on (`user_id`, `device_id`)

### test_runs table
Tracks FCM message delivery status for end-to-end testing:
- `nonce` - Unique test identifier (TEXT, PRIMARY KEY)
- `user_id` - User identifier (TEXT)
- `status` - Test status (TEXT: 'PENDING' or 'ACKED')
- `created_at` - Creation timestamp (TIMESTAMPTZ)
- `acked_at` - Acknowledgment timestamp (TIMESTAMPTZ, nullable)

## How to Initialize Schema

### Method 1: Automatic Initialization (Recommended)

The schema is automatically initialized when RDS is deployed using a Lambda function (`initSchema`).

**How it works:**
1. When RDS is created via Terraform, it automatically triggers the `initSchema` Lambda function
2. The Lambda function connects to RDS and executes the SQL in `init.sql`
3. Tables are created with `CREATE TABLE IF NOT EXISTS`, so it's safe to run multiple times

**Prerequisites:**
- RDS must be deployed
- `initSchema` Lambda function must be deployed
- Lambda must have VPC access to reach RDS

**Verification:**
After deployment, check CloudWatch Logs for the `initSchema` Lambda function:
```bash
# Get Lambda name from Terraform output
LAMBDA_NAME=$(cd infra/Lambdas && terraform output -raw init_schema_function_name)
aws logs tail /aws/lambda/$$LAMBDA_NAME --follow
```

You should see:
```
Successfully connected to RDS database
Schema initialized successfully!
Tables created: devices, test_runs
```

### Method 2: Manual Initialization via AWS CloudShell

If you need to manually initialize or re-run the schema:

1. **Open AWS CloudShell** in the AWS Console
2. **Install PostgreSQL client:**
   ```bash
   sudo yum install postgresql15 -y
   ```
3. **Get RDS connection information:**
   ```bash
   cd /path/to/FCM-Tutorial/infra/RDS
   terraform output rds_host
   terraform output rds_port
   terraform output rds_db_name
   terraform output rds_username
   ```
4. **Connect and execute SQL:**
   ```bash
   # Set environment variables (replace with actual values)
   export RDS_HOST="<from terraform output>"
   export RDS_PORT="<from terraform output>"
   export RDS_DB_NAME="<from terraform output>"
   export RDS_USERNAME="<from terraform output>"
   export RDS_PASSWORD="<your password>"
   
   # Execute SQL script
   PGPASSWORD=$RDS_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $RDS_USERNAME -d $RDS_DB_NAME -f /path/to/backend/Schema/init.sql
   ```

**Note:** CloudShell may not be able to access RDS if it's in a private subnet. In that case, use Method 1 (Lambda) or Method 3.

### Method 3: Manual Invocation of Lambda

You can manually trigger the `initSchema` Lambda function:

```bash
# Get Lambda function name
cd infra/Lambdas
LAMBDA_NAME=$(terraform output -raw init_schema_function_name)

# Invoke Lambda
aws lambda invoke \
  --function-name $LAMBDA_NAME \
  --payload '{}' \
  response.json

# Check response
cat response.json

# Check logs
aws logs tail /aws/lambda/$LAMBDA_NAME --follow
```

## How to Connect to RDS

### Security Constraints

According to the project requirements:
- **RDS is in a private subnet**
- **Security group: only Lambda can access**

This means:
- ❌ Cannot connect directly from your local machine
- ❌ Cannot use standard `psql` from local terminal
- ✅ Can connect via Lambda functions (they have VPC access)
- ✅ Can connect via AWS CloudShell (if it can reach the VPC)
- ✅ Can connect via EC2 instance in the same VPC (requires security group modification)

### Connection Methods

#### 1. Via Lambda Function (Recommended - Complies with Security Requirements)

The `initSchema` Lambda function automatically connects to RDS. You can also create custom Lambda functions to query the database.

**Advantages:**
- ✅ Complies with security requirements
- ✅ No security group changes needed
- ✅ Automated and repeatable

#### 2. Via AWS CloudShell

AWS CloudShell runs in AWS's network and may be able to access resources in your VPC.

**Steps:**
1. Open AWS CloudShell from the AWS Console
2. Install PostgreSQL client: `sudo yum install postgresql15 -y`
3. Connect using RDS endpoint and credentials

**Note:** This may not work if RDS is in a private subnet without proper network routing.

#### 3. Via EC2 Bastion Host (Requires Security Group Modification)

If you need direct database access for development/debugging:

1. Create an EC2 instance in the public subnet
2. Temporarily modify RDS security group to allow traffic from EC2 security group
3. SSH to EC2 and connect to RDS from there
4. **Important:** Remove the security group rule after use to maintain security compliance

**⚠️ Warning:** This violates the "only Lambda can access" requirement and should only be used for development/debugging.

## Verifying Schema Initialization

After initialization, verify the tables were created:

```sql
-- List all tables
\dt

-- Check devices table structure
\d devices

-- Check test_runs table structure
\d test_runs

-- Count records (should be 0 initially)
SELECT COUNT(*) FROM devices;
SELECT COUNT(*) FROM test_runs;
```

## Troubleshooting

### Lambda Function Not Executing

1. Check Lambda function exists:
   ```bash
   # Get Lambda name from Terraform output
   LAMBDA_NAME=$(cd infra/Lambdas && terraform output -raw init_schema_function_name)
   aws lambda get-function --function-name $$LAMBDA_NAME
   ```

2. Check CloudWatch Logs for errors:
   ```bash
   aws logs tail /aws/lambda/$$LAMBDA_NAME --follow
   ```

3. Verify Lambda has VPC configuration and can reach RDS

### Connection Timeout

- Verify RDS security group allows traffic from Lambda security group
- Check Lambda is in the same VPC as RDS
- Verify Lambda has VPC access permissions in IAM role

### Schema Already Exists Errors

The SQL uses `CREATE TABLE IF NOT EXISTS`, so it's safe to run multiple times. If you see errors, check:
- Table names are correct
- Permissions are sufficient
- Database connection is valid

