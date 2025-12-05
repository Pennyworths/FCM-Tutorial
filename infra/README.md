# Infrastructure (Terraform)

This directory contains Terraform configurations for deploying the FCM Tutorial infrastructure on AWS.

## Required Variables

### Database Credentials

| Variable | Environment Variable | Description |
|----------|---------------------|-------------|
| `db_username` | `TF_VAR_db_username` | Database master username |
| `db_password` | `TF_VAR_db_password` | Database master password |

### FCM Credentials

| Variable | Environment Variable | Description |
|----------|---------------------|-------------|
| `fcm_service_account_json_file` | `TF_VAR_fcm_service_account_json_file` | Path to FCM service account JSON file |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region |
| `project_name` | `fcm-tutorial` | Project name prefix |
| `environment` | `dev` | Environment (dev/staging/prod) |
| `image_tag` | `latest` | Docker image tag for Lambda functions |

## Setup

### 1. Download FCM Service Account JSON

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click **Project Settings** (gear icon) → **Service accounts**
4. Click **Generate new private key**
5. Save the downloaded file as `service-account.json` in the project root directory

### 2. Create `.env` file

Copy the example and fill in your values:

```bash
cp env.example .env
```

Edit `.env`:

```env
DB_USERNAME=your_db_username
DB_PASSWORD=your_secure_password
FCM_SERVICE_ACCOUNT_JSON_FILE=service-account.json
```

## How to Run

### Prerequisites: Configure AWS CLI

```bash
cd infra

# 1. Configure AWS credentials
make start

# 2. Verify credentials
make aws sts get-caller-identity
```

### Using Makefile (Recommended)

```bash
cd infra

# Initialize all modules
make init

# Plan all changes
make plan

# Deploy all infrastructure
make deploy-all
```

### Deploy Individual Modules

```bash
# Deploy in order (dependencies matter)
make deploy-vpc           # 1. VPC first
make deploy-secrets       # 2. Secrets Manager
make deploy-rds           # 3. RDS (requires VPC)
make deploy-lambdas       # 4. Lambda functions (requires VPC, RDS, Secrets)
make deploy-api-gateway   # 5. API Gateway (requires Lambdas)
```

### Using Terraform Directly

```bash
cd infra/VPC

# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Apply with auto-approve
terraform apply -auto-approve
```

## Expected Output

### Successful Deployment

After running `make deploy-all`, you should see:

```
===========================================
Infrastructure Deployment Complete!
===========================================

Summary:
  ✓ VPC: Deployed
  ✓ RDS: Deployed
  ✓ Secrets Manager: Deployed
  ✓ Lambda Functions: Deployed
  ✓ ECR Repository: Created
  ✓ API Gateway: Deployed
    API Base URL: https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/dev

Next Steps:
  1. Build and push Lambda images to ECR:
     make -C backend deploy
```

> ⚠️ **Important:** Save the `api_base_url` value. You will need it later for:
> - Android app configuration (`local.properties` → `API_BASE_URL`)
> - E2E testing (`.env` → `API_BASE_URL`)

### Output Values

Run `make output` to see all Terraform outputs. Key values:

| Output | Description |
|--------|-------------|
| `api_base_url` | API Gateway base URL |
| `rds_host` | RDS database host |
| `ecr_repository_url` | ECR repository for Lambda images |

## Useful Commands

```bash
# Show all outputs
make output

# Get API Gateway URL
make get-api-url

# Get ECR repository URL
make get-ecr-url

# Validate configurations
make validate

# Format Terraform files
make format

# Show current configuration
make config
```

## Destroy Infrastructure

```bash
# Destroy all (reverse order)
make destroy

# Destroy individual modules
make destroy-api-gateway
make destroy-lambdas
make destroy-secrets
make destroy-rds
make destroy-vpc
```

## Module Dependencies

```
VPC
 └── RDS
 └── Secrets
      └── Lambdas
           └── API_Gateway
```

Deploy in order: VPC → Secrets → RDS → Lambdas → API Gateway

Destroy in reverse order: API Gateway → Lambdas → Secrets → RDS → VPC

