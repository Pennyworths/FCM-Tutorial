#!/bin/bash
set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION="${AWS_REGION:-us-east-1}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AWS Profile (use terraform profile if AWS_PROFILE not set)
export AWS_PROFILE="${AWS_PROFILE:-terraform}"

echo -e "${BLUE}🚀 Deploying Lambda Functions${NC}"
echo -e "${BLUE}===========================================${NC}\n"

# Function to print step
print_step() {
    echo -e "\n${GREEN}📦 Step $1: $2${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Check prerequisites: Get required values from Terraform outputs
print_step "1" "Checking Prerequisites"

echo -e "${BLUE}Reading Terraform outputs from infra modules...${NC}"

# Check if infra/Lambdas exists and has been deployed
if [ ! -d "$PROJECT_ROOT/infra/Lambdas" ]; then
    echo -e "${RED}❌ Error: infra/Lambdas directory not found${NC}"
    echo -e "${YELLOW}Please deploy infrastructure first using terraform apply in infra/Lambdas${NC}"
    exit 1
fi

cd "$PROJECT_ROOT/infra/Lambdas"

# Get ECR repository URL
if ! ECR_REPO_URL=$(terraform output -raw ecr_repository_url 2>/dev/null); then
    echo -e "${RED}❌ Error: ECR repository not found${NC}"
    echo -e "${YELLOW}Please deploy infra/Lambdas module first:${NC}"
    echo -e "  cd infra/Lambdas"
    echo -e "  terraform init"
    echo -e "  terraform apply"
    exit 1
fi

# Get VPC info (needed for Lambda VPC config)
if [ -d "$PROJECT_ROOT/infra/VPC" ]; then
    cd "$PROJECT_ROOT/infra/VPC"
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids 2>/dev/null || echo "[]")
    LAMBDA_SG_ID=$(terraform output -raw lambda_security_group_id 2>/dev/null || echo "")
else
    echo -e "${YELLOW}⚠️  Warning: infra/VPC not found, using values from infra/Lambdas/terraform.tfvars${NC}"
    VPC_ID=""
    PRIVATE_SUBNET_IDS="[]"
    LAMBDA_SG_ID=""
fi

# Get RDS info (needed for Lambda environment variables)
if [ -d "$PROJECT_ROOT/infra/RDS" ]; then
    cd "$PROJECT_ROOT/infra/RDS"
    RDS_HOST=$(terraform output -raw rds_host 2>/dev/null || echo "placeholder")
    RDS_PORT=$(terraform output -raw rds_port 2>/dev/null || echo "5432")
    RDS_DB_NAME=$(terraform output -raw rds_db_name 2>/dev/null || echo "fcmdb")
    
    # Try to get credentials from terraform.tfvars
    if [ -f "$PROJECT_ROOT/infra/RDS/terraform.tfvars" ]; then
        RDS_USERNAME=$(grep "db_username" "$PROJECT_ROOT/infra/RDS/terraform.tfvars" | cut -d'"' -f2 || echo "")
        RDS_PASSWORD=$(grep "db_password" "$PROJECT_ROOT/infra/RDS/terraform.tfvars" | cut -d'"' -f2 || echo "")
    else
        RDS_USERNAME=""
        RDS_PASSWORD=""
    fi
else
    echo -e "${YELLOW}⚠️  Warning: infra/RDS not found, using placeholder values${NC}"
    RDS_HOST="placeholder"
    RDS_PORT="5432"
    RDS_DB_NAME="fcmdb"
    RDS_USERNAME=""
    RDS_PASSWORD=""
fi

# Get Secrets Manager ARN
if [ -d "$PROJECT_ROOT/infra/Secrets" ]; then
    cd "$PROJECT_ROOT/infra/Secrets"
    SECRET_ARN=$(terraform output -raw secret_arn 2>/dev/null || echo "")
else
    echo -e "${YELLOW}⚠️  Warning: infra/Secrets not found${NC}"
    SECRET_ARN=""
fi

echo -e "${GREEN}Prerequisites:${NC}"
echo -e "  ECR Repository: $ECR_REPO_URL"
if [ -n "$VPC_ID" ]; then
    echo -e "  VPC ID: $VPC_ID"
fi
if [ "$RDS_HOST" != "placeholder" ]; then
    echo -e "  RDS Host: $RDS_HOST"
fi

# Step 2: Build and push Docker images
print_step "2" "Building and Pushing Docker Images"

echo -e "${BLUE}ECR Repository: $ECR_REPO_URL${NC}\n"

# Login to ECR
echo -e "${BLUE}🔐 Logging in to ECR...${NC}"
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_REPO_URL

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to login to ECR. Check your AWS credentials.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Logged in to ECR${NC}\n"

# Build and push each function
cd "$PROJECT_ROOT/backend/Lambda"

FUNCTIONS=(
    "register:register.go:register-device"
    "send:send.go:send-message"
    "ack:ack.go:test-ack"
    "status:status.go:test-status"
    "init-schema:init-schema/main.go:init-schema"
)

IMAGE_TAG="${IMAGE_TAG:-latest}"

for func_info in "${FUNCTIONS[@]}"; do
    IFS=':' read -r func_name source_file image_name <<< "$func_info"
    
    echo -e "${BLUE}📦 Building $func_name function...${NC}"
    
    # Compile Go code
    echo -e "  Compiling Go code..."
    # For init-schema, build from its subdirectory
    if [[ "$source_file" == *"init-schema"* ]]; then
        cd init-schema
        # Download dependencies first
        echo -e "    Downloading Go dependencies..."
        go mod tidy
        GOOS=linux GOARCH=amd64 go build -o ../bootstrap main.go
        cd ..
        # Copy SQL schema file to Lambda directory for Docker build
        cp ../Schema/init.sql init.sql
    else
        GOOS=linux GOARCH=amd64 go build -o bootstrap "$source_file"
        # Create empty init.sql for other Lambdas (Dockerfile requires it)
        touch init.sql
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to compile $source_file${NC}"
        rm -f bootstrap
        exit 1
    fi
    
    # Build Docker image
    echo -e "  Building Docker image..."
    docker build -t "$image_name:$IMAGE_TAG" .
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to build Docker image for $func_name${NC}"
        rm -f bootstrap
        exit 1
    fi
    
    # Tag for ECR
    ECR_IMAGE="$ECR_REPO_URL:$image_name-$IMAGE_TAG"
    echo -e "  Tagging as $ECR_IMAGE..."
    docker tag "$image_name:$IMAGE_TAG" "$ECR_IMAGE"
    
    # Push to ECR
    echo -e "  Pushing to ECR..."
    docker push "$ECR_IMAGE"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to push $ECR_IMAGE${NC}"
        rm -f bootstrap
        exit 1
    fi
    
    # Cleanup
    rm -f bootstrap
    rm -f init.sql  # Clean up copied SQL file (for init-schema)
    docker rmi "$image_name:$IMAGE_TAG" 2>/dev/null || true
    
    echo -e "${GREEN}✅ $func_name function built and pushed successfully!${NC}"
    echo -e "   Image: $ECR_IMAGE\n"
done

echo -e "${GREEN}✅ Docker images built and pushed successfully${NC}"

# Step 3: Update Lambda functions with latest images
print_step "3" "Updating Lambda Functions"

cd "$PROJECT_ROOT/infra/Lambdas"

# Check if we have real RDS values
if [ "$RDS_HOST" = "placeholder" ] || [ -z "$RDS_USERNAME" ] || [ -z "$RDS_PASSWORD" ]; then
    echo -e "${YELLOW}⚠️  Warning: Using placeholder RDS values${NC}"
    echo -e "${YELLOW}Lambda functions will be created/updated with placeholder RDS connection info${NC}"
    echo -e "${YELLOW}You may need to update them later with real RDS values${NC}"
    RDS_HOST="${RDS_HOST:-placeholder}"
    RDS_PORT="${RDS_PORT:-5432}"
    RDS_DB_NAME="${RDS_DB_NAME:-fcmdb}"
    RDS_USERNAME="${RDS_USERNAME:-your_db_username}"
    RDS_PASSWORD="${RDS_PASSWORD:-your_db_password}"
fi

# Build terraform apply command
TERRAFORM_CMD="terraform apply -auto-approve"

# Add variables if available
if [ -n "$VPC_ID" ]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var=\"vpc_id=$VPC_ID\""
fi
if [ -n "$PRIVATE_SUBNET_IDS" ] && [ "$PRIVATE_SUBNET_IDS" != "[]" ]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var=\"private_subnet_ids=$PRIVATE_SUBNET_IDS\""
fi
if [ -n "$LAMBDA_SG_ID" ]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var=\"lambda_security_group_id=$LAMBDA_SG_ID\""
fi

TERRAFORM_CMD="$TERRAFORM_CMD -var=\"rds_host=$RDS_HOST\""
TERRAFORM_CMD="$TERRAFORM_CMD -var=\"rds_port=$RDS_PORT\""
TERRAFORM_CMD="$TERRAFORM_CMD -var=\"rds_db_name=$RDS_DB_NAME\""
TERRAFORM_CMD="$TERRAFORM_CMD -var=\"rds_username=$RDS_USERNAME\""
TERRAFORM_CMD="$TERRAFORM_CMD -var=\"rds_password=$RDS_PASSWORD\""

if [ -n "$SECRET_ARN" ]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var=\"secrets_manager_secret_arn=$SECRET_ARN\""
fi

echo -e "${BLUE}Running terraform apply...${NC}"
eval $TERRAFORM_CMD

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to update Lambda functions${NC}"
    exit 1
fi

# Get Lambda outputs
REGISTER_DEVICE_ARN=$(terraform output -raw register_device_function_arn 2>/dev/null || echo "")
REGISTER_DEVICE_NAME=$(terraform output -raw register_device_function_name 2>/dev/null || echo "")
SEND_MESSAGE_ARN=$(terraform output -raw send_message_function_arn 2>/dev/null || echo "")
SEND_MESSAGE_NAME=$(terraform output -raw send_message_function_name 2>/dev/null || echo "")
TEST_ACK_ARN=$(terraform output -raw test_ack_function_arn 2>/dev/null || echo "")
TEST_ACK_NAME=$(terraform output -raw test_ack_function_name 2>/dev/null || echo "")
TEST_STATUS_ARN=$(terraform output -raw test_status_function_arn 2>/dev/null || echo "")
TEST_STATUS_NAME=$(terraform output -raw test_status_function_name 2>/dev/null || echo "")
INIT_SCHEMA_NAME=$(terraform output -raw init_schema_function_name 2>/dev/null || echo "")

echo -e "${GREEN}Lambda Functions Updated:${NC}"
if [ -n "$REGISTER_DEVICE_NAME" ]; then
    echo -e "  ✅ Register Device: $REGISTER_DEVICE_NAME"
fi
if [ -n "$SEND_MESSAGE_NAME" ]; then
    echo -e "  ✅ Send Message: $SEND_MESSAGE_NAME"
fi
if [ -n "$TEST_ACK_NAME" ]; then
    echo -e "  ✅ Test Ack: $TEST_ACK_NAME"
fi
if [ -n "$TEST_STATUS_NAME" ]; then
    echo -e "  ✅ Test Status: $TEST_STATUS_NAME"
fi
if [ -n "$INIT_SCHEMA_NAME" ]; then
    echo -e "  ✅ Init Schema: $INIT_SCHEMA_NAME"
fi

# Step 4: Trigger init_schema Lambda if RDS is available and Lambda exists
if [ -n "$INIT_SCHEMA_NAME" ] && [ "$RDS_HOST" != "placeholder" ] && [ -n "$RDS_USERNAME" ] && [ -n "$RDS_PASSWORD" ]; then
    print_step "4" "Initializing Database Schema"
    
    echo -e "${BLUE}Triggering init_schema Lambda to initialize database schema...${NC}"
    
    # Wait for Lambda environment variables to propagate
    echo -e "${YELLOW}Waiting 10 seconds for Lambda environment variables to propagate...${NC}"
    sleep 10
    
    # Invoke init_schema Lambda with retry logic
    MAX_RETRIES=3
    RETRY_COUNT=0
    SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo -e "${YELLOW}Retry attempt $RETRY_COUNT of $MAX_RETRIES...${NC}"
            sleep 5
        fi
        
        echo -e "${BLUE}Invoking $INIT_SCHEMA_NAME...${NC}"
        INVOCATION_RESPONSE=$(aws lambda invoke \
            --function-name "$INIT_SCHEMA_NAME" \
            --region "$REGION" \
            --payload '{}' \
            /tmp/init_schema_response.json 2>&1)
        
        INVOCATION_EXIT_CODE=$?
        
        if [ $INVOCATION_EXIT_CODE -eq 0 ]; then
            # Check if there's an error in the response
            if grep -q "errorMessage" /tmp/init_schema_response.json 2>/dev/null; then
                ERROR_MSG=$(cat /tmp/init_schema_response.json | grep -o '"errorMessage":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
                
                # Check if it's a connection error (might be transient)
                if echo "$ERROR_MSG" | grep -qiE "(connection|timeout|unreachable|not available)"; then
                    echo -e "${YELLOW}⚠️  Connection error (may be transient): $ERROR_MSG${NC}"
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    continue
                else
                    echo -e "${RED}❌ init_schema Lambda execution failed: $ERROR_MSG${NC}"
                    echo -e "${YELLOW}Check CloudWatch Logs: /aws/lambda/$INIT_SCHEMA_NAME${NC}"
                    rm -f /tmp/init_schema_response.json
                    exit 1
                fi
            else
                # Success!
                SUCCESS=true
                echo -e "${GREEN}✅ init_schema Lambda executed successfully${NC}"
                echo -e "${BLUE}Checking CloudWatch Logs for verification...${NC}"
                sleep 5
                aws logs tail "/aws/lambda/$INIT_SCHEMA_NAME" --since 2m --region "$REGION" 2>/dev/null | tail -10 || echo -e "${YELLOW}Note: Could not fetch logs${NC}"
                rm -f /tmp/init_schema_response.json
                break
            fi
        else
            echo -e "${YELLOW}⚠️  Failed to invoke Lambda (exit code: $INVOCATION_EXIT_CODE)${NC}"
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
    
    if [ "$SUCCESS" = false ]; then
        echo -e "${RED}❌ Failed to invoke init_schema Lambda after $MAX_RETRIES attempts${NC}"
        echo -e "${YELLOW}You can manually invoke it later with:${NC}"
        echo -e "  aws lambda invoke --function-name $INIT_SCHEMA_NAME --region $REGION --payload '{}' response.json"
    fi
else
    if [ -z "$INIT_SCHEMA_NAME" ]; then
        echo -e "${YELLOW}⚠️  init_schema Lambda not found, skipping schema initialization${NC}"
    elif [ "$RDS_HOST" = "placeholder" ]; then
        echo -e "${YELLOW}⚠️  RDS not available yet, skipping schema initialization${NC}"
        echo -e "${YELLOW}Run this script again after RDS is deployed to initialize the schema${NC}"
    fi
fi

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}✅ Lambda Deployment Complete!${NC}"
echo -e "${GREEN}===========================================${NC}\n"

echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  ECR Repository: ${GREEN}$ECR_REPO_URL${NC}"
if [ "$RDS_HOST" != "placeholder" ]; then
    echo -e "  RDS Host: ${GREEN}$RDS_HOST${NC}"
fi
echo -e "\n${YELLOW}⚠️  Note:${NC}"
echo -e "  Infrastructure (VPC, RDS, Secrets, API Gateway) should be deployed separately"
echo -e "  using terraform init/plan/apply in each infra module directory"
echo -e "\n"

