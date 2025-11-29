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
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AWS Profile (use terraform profile if AWS_PROFILE not set)
export AWS_PROFILE="${AWS_PROFILE:-terraform}"

# Load environment variables for Terraform
# These can be set in .env file or exported before running deploy.sh
# Required: DB_USERNAME, DB_PASSWORD, FCM_SERVICE_ACCOUNT_JSON or FCM_SERVICE_ACCOUNT_JSON_FILE
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${BLUE}Loading environment variables from .env file...${NC}"
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Set Terraform variables from environment variables
export TF_VAR_db_username="${DB_USERNAME:-}"
export TF_VAR_db_password="${DB_PASSWORD:-}"
export TF_VAR_rds_username="${RDS_USERNAME:-${DB_USERNAME:-}}"
export TF_VAR_rds_password="${RDS_PASSWORD:-${DB_PASSWORD:-}}"

# FCM Service Account JSON can be provided as:
# 1. FCM_SERVICE_ACCOUNT_JSON (JSON string)
# 2. FCM_SERVICE_ACCOUNT_JSON_FILE (file path)
if [ -n "$FCM_SERVICE_ACCOUNT_JSON" ]; then
    export TF_VAR_fcm_service_account_json="$FCM_SERVICE_ACCOUNT_JSON"
elif [ -n "$FCM_SERVICE_ACCOUNT_JSON_FILE" ]; then
    export TF_VAR_fcm_service_account_json_file="$FCM_SERVICE_ACCOUNT_JSON_FILE"
elif [ -f "$PROJECT_ROOT/service-account.json" ]; then
    # Fallback to service-account.json in project root
    export TF_VAR_fcm_service_account_json_file="$PROJECT_ROOT/service-account.json"
fi

echo -e "${BLUE}Starting FCM Infrastructure Deployment${NC}"
echo -e "${BLUE}===========================================${NC}\n"

# Function to print step
print_step() {
    echo -e "\n${GREEN}Step $1: $2${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Function to run terraform in a module
terraform_apply() {
    local module_dir=$1
    local description=$2
    shift 2
    local extra_vars=("$@")
    
    cd "$PROJECT_ROOT/$module_dir"
    
    echo -e "${BLUE}Initializing Terraform...${NC}"
    terraform init -upgrade
    
    # Refresh state to sync with actual resources (handles interrupted deployments)
    echo -e "${BLUE}Refreshing state...${NC}"
    if [ ${#extra_vars[@]} -eq 0 ]; then
        terraform refresh -auto-approve > /dev/null 2>&1 || true
    else
        terraform refresh -auto-approve "${extra_vars[@]}" > /dev/null 2>&1 || true
    fi
    
    echo -e "${BLUE}Planning...${NC}"
    if [ ${#extra_vars[@]} -eq 0 ]; then
        terraform plan
    else
        terraform plan "${extra_vars[@]}"
    fi
    
    echo -e "${BLUE}Applying...${NC}"
    if [ ${#extra_vars[@]} -eq 0 ]; then
        terraform apply -auto-approve
    else
        terraform apply -auto-approve "${extra_vars[@]}"
    fi
    
    echo -e "${GREEN}$description deployed successfully!${NC}"
}

# Step 1: Deploy VPC
print_step "1" "Deploying VPC"
# VPC doesn't need extra vars, so we can use the simple form
terraform_apply "infra/VPC" "VPC"

# Get VPC outputs
cd "$PROJECT_ROOT/infra/VPC"
VPC_ID=$(terraform output -raw vpc_id)
PRIVATE_SUBNET_IDS=$(terraform output -json private_subnet_ids)
LAMBDA_SG_ID=$(terraform output -raw lambda_security_group_id)

echo -e "${GREEN}VPC Outputs:${NC}"
echo -e "  VPC ID: $VPC_ID"
echo -e "  Private Subnets: $PRIVATE_SUBNET_IDS"
echo -e "  Lambda SG ID: $LAMBDA_SG_ID"

# Step 2: Deploy RDS
print_step "2" "Deploying RDS"
cd "$PROJECT_ROOT/infra/RDS"

# Check if required environment variables are set
if [ -z "$TF_VAR_db_username" ] || [ -z "$TF_VAR_db_password" ]; then
    echo -e "${RED}Error: DB credentials not found!${NC}"
    echo -e "${YELLOW}Please set the following environment variables:${NC}"
    echo -e "  export DB_USERNAME=\"your_username\""
    echo -e "  export DB_PASSWORD=\"your_password\""
    echo -e "${YELLOW}Or create a .env file in the project root with:${NC}"
    echo -e "  DB_USERNAME=your_username"
    echo -e "  DB_PASSWORD=your_password"
    exit 1
fi

# RDS needs VPC info, but we'll refresh state first to handle existing resources
terraform_apply "infra/RDS" "RDS" \
    -var="vpc_id=$VPC_ID" \
    -var="private_subnet_ids=$PRIVATE_SUBNET_IDS" \
    -var="lambda_security_group_id=$LAMBDA_SG_ID" \
    -var="db_username=$TF_VAR_db_username" \
    -var="db_password=$TF_VAR_db_password"

# Get RDS outputs
cd "$PROJECT_ROOT/infra/RDS"
RDS_HOST=$(terraform output -raw rds_host)
RDS_PORT=$(terraform output -raw rds_port)
RDS_DB_NAME=$(terraform output -raw rds_db_name)

echo -e "${GREEN}RDS Outputs:${NC}"
echo -e "  RDS Host: $RDS_HOST"
echo -e "  RDS Port: $RDS_PORT"
echo -e "  RDS DB Name: $RDS_DB_NAME"

# Step 3: Deploy Secrets
print_step "3" "Deploying Secrets Manager"
cd "$PROJECT_ROOT/infra/Secrets"

# Check if FCM service account JSON is provided
if [ -z "$TF_VAR_fcm_service_account_json" ] && [ -z "$TF_VAR_fcm_service_account_json_file" ]; then
    echo -e "${RED}Error: FCM service account JSON not found!${NC}"
    echo -e "${YELLOW}Please provide one of the following:${NC}"
    echo -e "  1. Set FCM_SERVICE_ACCOUNT_JSON environment variable (JSON string)"
    echo -e "  2. Set FCM_SERVICE_ACCOUNT_JSON_FILE environment variable (file path)"
    echo -e "  3. Place service-account.json in project root"
    echo -e "${YELLOW}Or add to .env file:${NC}"
    echo -e "  FCM_SERVICE_ACCOUNT_JSON_FILE=/path/to/service-account.json"
    exit 1
fi

# Deploy Secrets Manager with RDS password
cd "$PROJECT_ROOT/infra/Secrets"
terraform_apply "infra/Secrets" "Secrets Manager" \
    -var="rds_password=$TF_VAR_rds_password"

# Get Secrets outputs
cd "$PROJECT_ROOT/infra/Secrets"
SECRET_ARN=$(terraform output -raw secret_arn)
RDS_PASSWORD_SECRET_ARN=$(terraform output -raw rds_password_secret_arn)

echo -e "${GREEN}Secrets Output:${NC}"
echo -e "  FCM Secret ARN: $SECRET_ARN"
echo -e "  RDS Password Secret ARN: $RDS_PASSWORD_SECRET_ARN"

# Step 4: Deploy Lambdas (in phases to avoid image not found errors)
print_step "4a" "Creating ECR Repository and IAM Roles for Lambda"
cd "$PROJECT_ROOT/infra/Lambdas"

# Check if required environment variables are set
if [ -z "$TF_VAR_rds_username" ]; then
    echo -e "${RED}Error: RDS username not found!${NC}"
    echo -e "${YELLOW}Please set the following environment variable:${NC}"
    echo -e "  export RDS_USERNAME=\"your_username\" (or DB_USERNAME)"
    echo -e "${YELLOW}Or create a .env file in the project root with:${NC}"
    echo -e "  RDS_USERNAME=your_username"
    exit 1
fi

# RDS password is now stored in Secrets Manager, but we still need it for RDS creation
if [ -z "$TF_VAR_rds_password" ]; then
    echo -e "${RED}Error: RDS password not found!${NC}"
    echo -e "${YELLOW}Please set the following environment variable:${NC}"
    echo -e "  export RDS_PASSWORD=\"your_password\" (or DB_PASSWORD)"
    echo -e "${YELLOW}Or create a .env file in the project root with:${NC}"
    echo -e "  RDS_PASSWORD=your_password"
    exit 1
fi

# Initialize Terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init -upgrade

# Prepare terraform variables array (Terraform variables are set via TF_VAR_* environment variables)
TF_VARS=(
    "-var=vpc_id=$VPC_ID"
    "-var=private_subnet_ids=$PRIVATE_SUBNET_IDS"
    "-var=lambda_security_group_id=$LAMBDA_SG_ID"
    "-var=rds_host=$RDS_HOST"
    "-var=rds_port=$RDS_PORT"
    "-var=rds_db_name=$RDS_DB_NAME"
    "-var=secrets_manager_secret_arn=$SECRET_ARN"
    "-var=rds_password_secret_arn=$RDS_PASSWORD_SECRET_ARN"
)

# Create ECR repository and IAM roles first (without Lambda functions)
# This avoids the "image not found" error when creating Lambda functions
echo -e "${BLUE}Creating ECR repository and IAM roles (without Lambda functions)...${NC}"
terraform apply -auto-approve \
    -target=aws_iam_role.lambda \
    -target=aws_iam_role_policy_attachment.lambda_vpc \
    -target=aws_iam_role_policy_attachment.lambda_logs \
    -target=aws_iam_role_policy.lambda_secrets \
    -target=aws_ecr_repository.lambda_images \
    -target=aws_ecr_lifecycle_policy.lambda_images \
    "${TF_VARS[@]}" || {
    echo -e "${YELLOW}Note: Some resources may already exist or there were warnings.${NC}"
    echo -e "${BLUE}Continuing...${NC}"
}

# Get ECR repository URL
ECR_REPO_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
if [ -z "$ECR_REPO_URL" ]; then
    echo -e "${RED}Error: Failed to get ECR repository URL${NC}"
    exit 1
fi

echo -e "${GREEN}ECR Repository: $ECR_REPO_URL${NC}"

# Step 4b: Build and push Lambda images to ECR
print_step "4b" "Building and Pushing Lambda Images to ECR"

echo -e "${BLUE}Creating and pushing placeholder images...${NC}"

# Login to ECR
echo -e "${BLUE}Logging in to ECR...${NC}"
if ! aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPO_URL"; then
    echo -e "${RED}Failed to login to ECR. Check your AWS credentials.${NC}"
    exit 1
fi

echo -e "${GREEN}Logged in to ECR${NC}\n"

# Pull AWS Lambda base image
echo -e "${BLUE}Pulling AWS Lambda base image...${NC}"
if ! docker pull public.ecr.aws/lambda/provided:al2023; then
    echo -e "${RED}Failed to pull base image${NC}"
    exit 1
fi

echo -e "${GREEN}Base image pulled${NC}\n"

# Build and push images for each function
FUNCTIONS=(
    "register-device"
    "send-message"
    "test-ack"
    "test-status"
    "init-schema"
)

IMAGE_TAG="${IMAGE_TAG:-latest}"

# Save current directory
ORIGINAL_DIR=$(pwd)

for func_tag in "${FUNCTIONS[@]}"; do
    LAMBDA_DIR="$PROJECT_ROOT/backend/Lambda/$func_tag"
    ECR_IMAGE="$ECR_REPO_URL:$func_tag-$IMAGE_TAG"
    
    # Check if Lambda has a Dockerfile (actual code)
    if [ -f "$LAMBDA_DIR/Dockerfile" ]; then
        echo -e "${BLUE}Building actual image for $func_tag...${NC}"
        echo -e "  Directory: $LAMBDA_DIR"
        
        # Build the Docker image
        # For init-schema and functions in API directory, we need to include the Schema directory in build context
        # Lambda requires: Single-architecture image (linux/amd64) with Docker Manifest V2 Schema 2
        # Use buildx with --load to create single-arch image compatible with Lambda
        if [ "$func_tag" = "init-schema" ]; then
            cd "$PROJECT_ROOT/backend"
            # First, ensure we have amd64 base images
            docker pull --platform linux/amd64 golang:1.23-alpine > /dev/null 2>&1 || true
            docker pull --platform linux/amd64 public.ecr.aws/lambda/provided:al2023 > /dev/null 2>&1 || true
            if ! docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false -f "Lambda/$func_tag/Dockerfile" -t "$ECR_IMAGE" .; then
                echo -e "${RED}Failed to build $func_tag image${NC}"
                cd "$ORIGINAL_DIR"
                exit 1
            fi
        elif [ -f "$PROJECT_ROOT/backend/Lambda/API/Dockerfile" ]; then
            # All API functions (register-device, send-message, test-ack, test-status) share the same Dockerfile
            # Build from backend/ directory to access Schema/
            cd "$PROJECT_ROOT/backend"
            # First, ensure we have amd64 base images
            docker pull --platform linux/amd64 golang:1.23-alpine > /dev/null 2>&1 || true
            docker pull --platform linux/amd64 public.ecr.aws/lambda/provided:al2023 > /dev/null 2>&1 || true
            if ! docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false -f "Lambda/API/Dockerfile" -t "$ECR_IMAGE" .; then
                echo -e "${RED}Failed to build $func_tag image${NC}"
                cd "$ORIGINAL_DIR"
                exit 1
            fi
        else
            cd "$LAMBDA_DIR"
            # Ensure base image is amd64
            docker pull --platform linux/amd64 public.ecr.aws/lambda/provided:al2023 > /dev/null 2>&1 || true
            if ! docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false -t "$ECR_IMAGE" .; then
                echo -e "${RED}Failed to build $func_tag image${NC}"
                cd "$ORIGINAL_DIR"
                exit 1
            fi
        fi
        
        # Push to ECR
        echo -e "  Pushing to $ECR_IMAGE..."
        if ! docker push "$ECR_IMAGE"; then
            echo -e "${RED}Failed to push $ECR_IMAGE${NC}"
            cd "$ORIGINAL_DIR"
            exit 1
        fi
        
        # Cleanup local image
        docker rmi "$ECR_IMAGE" 2>/dev/null || true
        
        # Return to original directory
        cd "$ORIGINAL_DIR"
        
        echo -e "${GREEN}$func_tag actual image built and pushed!${NC}"
        echo -e "   Image: $ECR_IMAGE\n"
    else
        # No Dockerfile found, use placeholder
        echo -e "${YELLOW}No Dockerfile found for $func_tag, using placeholder...${NC}"
        
        # Create a minimal Dockerfile for placeholder to ensure single-arch manifest
        PLACEHOLDER_DOCKERFILE=$(mktemp)
        cat > "$PLACEHOLDER_DOCKERFILE" << 'EOF'
FROM public.ecr.aws/lambda/provided:al2023
# Minimal placeholder image
EOF
        
        # Build placeholder image using buildx to ensure single-arch manifest
        cd "$PROJECT_ROOT"
        if ! docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false -f "$PLACEHOLDER_DOCKERFILE" -t "$ECR_IMAGE" .; then
            echo -e "${RED}Failed to build $func_tag placeholder image${NC}"
            rm -f "$PLACEHOLDER_DOCKERFILE"
            cd "$ORIGINAL_DIR"
            exit 1
        fi
        rm -f "$PLACEHOLDER_DOCKERFILE"
        
        # Push to ECR
        echo -e "  Pushing placeholder to $ECR_IMAGE..."
        if ! docker push "$ECR_IMAGE"; then
            echo -e "${RED}Failed to push $ECR_IMAGE${NC}"
            cd "$ORIGINAL_DIR"
            exit 1
        fi
        
        # Cleanup local tag
        docker rmi "$ECR_IMAGE" 2>/dev/null || true
        
        echo -e "${GREEN}$func_tag placeholder image created and pushed!${NC}"
        echo -e "   Image: $ECR_IMAGE\n"
    fi
done

echo -e "${GREEN}All images pushed successfully${NC}\n"

# Step 4c: Deploy Lambda Functions (now that images exist in ECR)
print_step "4c" "Deploying Lambda Functions"
cd "$PROJECT_ROOT/infra/Lambdas"

echo -e "${BLUE}Creating Lambda functions (images now exist in ECR)...${NC}"
# Now apply all resources, which will create the Lambda functions
# Terraform variables (rds_username) are set via TF_VAR_* environment variables
# Note: rds_password is now stored in Secrets Manager, not passed directly to Lambda
terraform apply -auto-approve "${TF_VARS[@]}" \
    -var="rds_username=$TF_VAR_rds_username"

# Get Lambda outputs
REGISTER_DEVICE_ARN=$(terraform output -raw register_device_function_arn)
REGISTER_DEVICE_NAME=$(terraform output -raw register_device_function_name)
SEND_MESSAGE_ARN=$(terraform output -raw send_message_function_arn)
SEND_MESSAGE_NAME=$(terraform output -raw send_message_function_name)
TEST_ACK_ARN=$(terraform output -raw test_ack_function_arn)
TEST_ACK_NAME=$(terraform output -raw test_ack_function_name)
TEST_STATUS_ARN=$(terraform output -raw test_status_function_arn)
TEST_STATUS_NAME=$(terraform output -raw test_status_function_name)
INIT_SCHEMA_NAME=$(terraform output -raw init_schema_function_name 2>/dev/null || echo "")

echo -e "${GREEN}Lambda Functions deployed successfully!${NC}"
echo -e "${GREEN}Lambda Outputs:${NC}"
echo -e "  Register Device ARN: $REGISTER_DEVICE_ARN"
echo -e "  Send Message ARN: $SEND_MESSAGE_ARN"
echo -e "  Test Ack ARN: $TEST_ACK_ARN"
echo -e "  Test Status ARN: $TEST_STATUS_ARN"
echo -e "  Init Schema Name: $INIT_SCHEMA_NAME"
echo -e "  ECR Repository: $ECR_REPO_URL"

# Step 4d: Update RDS to trigger init-schema Lambda (if Lambda name is available)
if [ -n "$INIT_SCHEMA_NAME" ]; then
    print_step "4d" "Updating RDS to trigger init-schema Lambda"
    cd "$PROJECT_ROOT/infra/RDS"
    terraform apply -auto-approve \
        -var="vpc_id=$VPC_ID" \
        -var="private_subnet_ids=$PRIVATE_SUBNET_IDS" \
        -var="lambda_security_group_id=$LAMBDA_SG_ID" \
        -var="init_schema_lambda_name=$INIT_SCHEMA_NAME"
    echo -e "${GREEN}RDS updated to trigger init-schema Lambda${NC}"
fi

# Step 5: Deploy API Gateway
print_step "5" "Deploying API Gateway"
terraform_apply "infra/API_Gateway" "API Gateway" \
    -var="register_device_lambda_arn=$REGISTER_DEVICE_ARN" \
    -var="register_device_lambda_name=$REGISTER_DEVICE_NAME" \
    -var="send_message_lambda_arn=$SEND_MESSAGE_ARN" \
    -var="send_message_lambda_name=$SEND_MESSAGE_NAME" \
    -var="test_ack_lambda_arn=$TEST_ACK_ARN" \
    -var="test_ack_lambda_name=$TEST_ACK_NAME" \
    -var="test_status_lambda_arn=$TEST_STATUS_ARN" \
    -var="test_status_lambda_name=$TEST_STATUS_NAME"

# Get API Gateway output
cd "$PROJECT_ROOT/infra/API_Gateway"
API_BASE_URL=$(terraform output -raw api_base_url)

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}===========================================${NC}\n"

echo -e "${BLUE}Summary:${NC}"
echo -e "  API Base URL: ${GREEN}$API_BASE_URL${NC}"
echo -e "  ECR Repository: ${GREEN}$ECR_REPO_URL${NC}"
echo -e "  RDS Host: ${GREEN}$RDS_HOST${NC}"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "  1. Lambda images have been built and pushed to ECR"
echo -e "  2. Lambda functions are deployed and ready to use"
echo -e "  3. Test API endpoints using the base URL above"
echo -e "\n${BLUE}Note:${NC}"
echo -e "  - Lambda functions with Dockerfile were built with actual code"
echo -e "  - Lambda functions without Dockerfile are using placeholder images"
echo -e "  - To add code to placeholder Lambdas, create a Dockerfile in their directory"
echo -e "\n"

