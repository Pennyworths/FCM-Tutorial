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
# Get the directory where this script is located, then go up one level to get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# AWS Profile (use terraform profile if AWS_PROFILE not set)
export AWS_PROFILE="${AWS_PROFILE:-terraform}"

# Load environment variables for Terraform
# These can be set in .env file or exported before running this script
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

# Function to print usage
usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo "Options:"
    echo "  --skip-lambdas        Skip Lambda deployment (useful if images not ready)"
    echo "  --skip-api-gateway    Skip API Gateway deployment"
    echo "  --auto-approve        Auto-approve all Terraform operations (default: true)"
    echo "  --no-auto-approve     Require confirmation for Terraform operations"
    echo "  -t, --tag TAG         Docker image tag (default: latest, required for Lambda deployment)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DB_USERNAME           Database username (required)"
    echo "  DB_PASSWORD           Database password (required)"
    echo "  FCM_SERVICE_ACCOUNT_JSON_FILE  Path to FCM service account JSON file"
    echo "  IMAGE_TAG             Docker image tag (default: latest)"
    echo "  AWS_REGION            AWS region (default: us-east-1)"
    echo "  AWS_PROFILE           AWS profile (default: terraform)"
    echo ""
    echo "Example:"
    echo "  $0 --tag v1.0.0       # Deploy with specific image tag"
    echo "  $0                    # Deploy with default tag (latest)"
    echo "  $0 --skip-lambdas     # Deploy everything except Lambdas"
    exit 1
}

# Parse command line arguments
SKIP_LAMBDAS=false
SKIP_API_GATEWAY=false
AUTO_APPROVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-lambdas)
            SKIP_LAMBDAS=true
            shift
            ;;
        --skip-api-gateway)
            SKIP_API_GATEWAY=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --no-auto-approve)
            AUTO_APPROVE=false
            shift
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}FCM Infrastructure Deployment${NC}"
echo -e "${BLUE}===========================================${NC}\n"

echo -e "${BLUE}Configuration:${NC}"
echo -e "  AWS Region: ${GREEN}$REGION${NC}"
echo -e "  AWS Profile: ${GREEN}$AWS_PROFILE${NC}"
echo -e "  Project Root: ${GREEN}$PROJECT_ROOT${NC}"
echo -e "  Image Tag: ${GREEN}$IMAGE_TAG${NC}"
echo -e "  Auto Approve: ${GREEN}$AUTO_APPROVE${NC}"
echo ""

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
    if [ "$AUTO_APPROVE" = true ]; then
        if [ ${#extra_vars[@]} -eq 0 ]; then
            terraform apply -auto-approve
        else
            terraform apply -auto-approve "${extra_vars[@]}"
        fi
    else
        if [ ${#extra_vars[@]} -eq 0 ]; then
            terraform apply
        else
            terraform apply "${extra_vars[@]}"
        fi
    fi
    
    echo -e "${GREEN}$description deployed successfully!${NC}"
}

# Step 1: Deploy VPC
print_step "1" "Deploying VPC"
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

# Step 3: Deploy Secrets Manager
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

terraform_apply "infra/Secrets" "Secrets Manager" \
    -var="rds_password=$TF_VAR_rds_password"

# Get Secrets outputs
cd "$PROJECT_ROOT/infra/Secrets"
SECRET_ARN=$(terraform output -raw secret_arn)
RDS_PASSWORD_SECRET_ARN=$(terraform output -raw rds_password_secret_arn)

echo -e "${GREEN}Secrets Output:${NC}"
echo -e "  FCM Secret ARN: $SECRET_ARN"
echo -e "  RDS Password Secret ARN: $RDS_PASSWORD_SECRET_ARN"

# Step 4: Deploy Lambdas (if not skipped)
if [ "$SKIP_LAMBDAS" = false ]; then
    print_step "4" "Deploying Lambda Functions and ECR"
    cd "$PROJECT_ROOT/infra/Lambdas"
    
    # Check if required environment variables are set
    if [ -z "$TF_VAR_rds_username" ]; then
        echo -e "${RED}Error: RDS username not found!${NC}"
        echo -e "${YELLOW}Please set the following environment variable:${NC}"
        echo -e "  export RDS_USERNAME=\"your_username\" (or DB_USERNAME)"
        exit 1
    fi
    
    if [ -z "$TF_VAR_rds_password" ]; then
        echo -e "${RED}Error: RDS password not found!${NC}"
        echo -e "${YELLOW}Please set the following environment variable:${NC}"
        echo -e "  export RDS_PASSWORD=\"your_password\" (or DB_PASSWORD)"
        exit 1
    fi
    
    # Prepare terraform variables array
    TF_VARS=(
        "-var=vpc_id=$VPC_ID"
        "-var=private_subnet_ids=$PRIVATE_SUBNET_IDS"
        "-var=lambda_security_group_id=$LAMBDA_SG_ID"
        "-var=rds_host=$RDS_HOST"
        "-var=rds_port=$RDS_PORT"
        "-var=rds_db_name=$RDS_DB_NAME"
        "-var=secrets_manager_secret_arn=$SECRET_ARN"
        "-var=rds_password_secret_arn=$RDS_PASSWORD_SECRET_ARN"
        "-var=rds_username=$TF_VAR_rds_username"
        "-var=image_tag=$IMAGE_TAG"
    )
    
    # Initialize Terraform
    echo -e "${BLUE}Initializing Terraform...${NC}"
    terraform init -upgrade
    
    # Create ECR repository and IAM roles first (without Lambda functions)
    echo -e "${BLUE}Creating ECR repository and IAM roles...${NC}"
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
    
    # Create and push placeholder images so Lambda functions can be created
    print_step "4a" "Creating Placeholder Images for Lambda Functions"
    
    # Check if Docker is running
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running!${NC}"
        echo -e "${YELLOW}Please start Docker Desktop and try again.${NC}"
        exit 1
    fi
    
    # Login to ECR
    echo -e "${BLUE}Logging in to ECR...${NC}"
    if ! aws ecr get-login-password --region "$REGION" --profile "$AWS_PROFILE" | \
        docker login --username AWS --password-stdin "$ECR_REPO_URL" > /dev/null 2>&1; then
        echo -e "${RED}Failed to login to ECR. Check your AWS credentials.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Logged in to ECR${NC}"
    
    # Pull base image
    echo -e "${BLUE}Pulling base image...${NC}"
    docker pull --platform linux/amd64 public.ecr.aws/lambda/provided:al2023 > /dev/null 2>&1 || true
    
    # Create placeholder images for all Lambda functions
    # IMAGE_TAG is already set from environment or command line
    FUNCTIONS=("register-device" "send-message" "test-ack" "test-status" "init-schema")
    
    echo -e "${BLUE}Creating placeholder images...${NC}"
    PLACEHOLDER_DOCKERFILE=$(mktemp)
    cat > "$PLACEHOLDER_DOCKERFILE" << 'EOF'
FROM public.ecr.aws/lambda/provided:al2023
# Minimal placeholder image - will be replaced by actual images via backend deploy
EOF
    
    for func_tag in "${FUNCTIONS[@]}"; do
        ECR_IMAGE="$ECR_REPO_URL:$func_tag-$IMAGE_TAG"
        echo -e "${BLUE}  Creating placeholder: $func_tag...${NC}"
        
        # Build placeholder image
        cd "$PROJECT_ROOT"
        if ! docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false \
            -f "$PLACEHOLDER_DOCKERFILE" -t "$ECR_IMAGE" . > /dev/null 2>&1; then
            echo -e "${RED}Failed to build placeholder for $func_tag${NC}"
            rm -f "$PLACEHOLDER_DOCKERFILE"
            exit 1
        fi
        
        # Push to ECR
        if ! docker push "$ECR_IMAGE" > /dev/null 2>&1; then
            echo -e "${RED}Failed to push placeholder for $func_tag${NC}"
            rm -f "$PLACEHOLDER_DOCKERFILE"
            exit 1
        fi
        
        # Cleanup local image
        docker rmi "$ECR_IMAGE" 2>/dev/null || true
    done
    
    rm -f "$PLACEHOLDER_DOCKERFILE"
    echo -e "${GREEN}✓ Placeholder images created and pushed${NC}"
    echo -e "${YELLOW}Note: You can update these images later using: make -C backend deploy${NC}\n"
    
    # Deploy Lambda Functions (now that placeholder images exist)
    # Ensure we're in the correct directory (may have changed during image building)
    cd "$PROJECT_ROOT/infra/Lambdas"
    echo -e "${BLUE}Deploying Lambda functions...${NC}"
    if [ "$AUTO_APPROVE" = true ]; then
        terraform apply -auto-approve "${TF_VARS[@]}"
    else
        terraform apply "${TF_VARS[@]}"
    fi
    
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
    
    # Update RDS to trigger init-schema Lambda (if Lambda name is available)
    # Note: This will fail if Lambda is using placeholder image.
    # Skip this step during initial deployment, run it after deploying actual backend images.
    if [ -n "$INIT_SCHEMA_NAME" ]; then
        print_step "4b" "Updating RDS to trigger init-schema Lambda"
        echo -e "${YELLOW}⚠️  Warning: This step will fail if Lambda is using placeholder image.${NC}"
        echo -e "${YELLOW}   This is expected during initial deployment.${NC}"
        echo -e "${YELLOW}   The deployment will continue even if this step fails.${NC}"
        echo ""
        
        # Try to trigger init-schema, but don't fail the entire deployment if it fails
        # Use set +e to allow the command to fail without exiting
        set +e
        cd "$PROJECT_ROOT/infra/RDS"
        terraform init -upgrade > /dev/null 2>&1
        terraform apply -auto-approve \
            -var="vpc_id=$VPC_ID" \
            -var="private_subnet_ids=$PRIVATE_SUBNET_IDS" \
            -var="lambda_security_group_id=$LAMBDA_SG_ID" \
            -var="init_schema_lambda_name=$INIT_SCHEMA_NAME" \
            -var="db_username=$TF_VAR_db_username" \
            -var="db_password=$TF_VAR_db_password" 2>&1
        INIT_SCHEMA_RESULT=$?
        set -e
        
        if [ $INIT_SCHEMA_RESULT -ne 0 ]; then
            echo -e "\n${YELLOW}⚠️  init-schema Lambda invocation failed (expected if using placeholder image)${NC}"
            echo -e "${BLUE}This is normal during initial deployment. To initialize schema later:${NC}"
            echo -e "${GREEN}  1. Deploy actual backend images:${NC}"
            echo -e "${GREEN}     cd backend && make deploy IMAGE_TAG=$IMAGE_TAG${NC}"
            echo -e "${GREEN}  2. Then trigger init-schema:${NC}"
            echo -e "${GREEN}     cd infra/RDS${NC}"
            echo -e "${GREEN}     terraform apply -auto-approve -var=\"vpc_id=$VPC_ID\" -var=\"private_subnet_ids=$PRIVATE_SUBNET_IDS\" -var=\"lambda_security_group_id=$LAMBDA_SG_ID\" -var=\"init_schema_lambda_name=$INIT_SCHEMA_NAME\" -var=\"db_username=$TF_VAR_db_username\" -var=\"db_password=$TF_VAR_db_password\"${NC}"
            echo ""
        else
            echo -e "${GREEN}✓ Schema initialization triggered successfully${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Skipping Lambda deployment (--skip-lambdas flag set)${NC}"
    REGISTER_DEVICE_ARN=""
    REGISTER_DEVICE_NAME=""
    SEND_MESSAGE_ARN=""
    SEND_MESSAGE_NAME=""
    TEST_ACK_ARN=""
    TEST_ACK_NAME=""
    TEST_STATUS_ARN=""
    TEST_STATUS_NAME=""
fi

# Step 5: Deploy API Gateway (if not skipped and Lambdas are deployed)
if [ "$SKIP_API_GATEWAY" = false ] && [ "$SKIP_LAMBDAS" = false ]; then
    if [ -n "$REGISTER_DEVICE_ARN" ] && [ -n "$SEND_MESSAGE_ARN" ]; then
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
        
        echo -e "${GREEN}API Gateway deployed successfully!${NC}"
        echo -e "${GREEN}API Base URL: $API_BASE_URL${NC}"
    else
        echo -e "${YELLOW}Skipping API Gateway: Lambda outputs not available${NC}"
    fi
elif [ "$SKIP_API_GATEWAY" = true ]; then
    echo -e "${YELLOW}Skipping API Gateway deployment (--skip-api-gateway flag set)${NC}"
fi

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}Infrastructure Deployment Complete!${NC}"
echo -e "${GREEN}===========================================${NC}\n"

echo -e "${BLUE}Summary:${NC}"
echo -e "  ✓ VPC: Deployed"
echo -e "  ✓ RDS: Deployed"
echo -e "  ✓ Secrets Manager: Deployed"
if [ "$SKIP_LAMBDAS" = false ]; then
    echo -e "  ✓ Lambda Functions: Deployed"
    echo -e "  ✓ ECR Repository: Created"
else
    echo -e "  ⏭ Lambda Functions: Skipped"
fi
if [ "$SKIP_API_GATEWAY" = false ] && [ "$SKIP_LAMBDAS" = false ]; then
    if [ -n "$API_BASE_URL" ]; then
        echo -e "  ✓ API Gateway: Deployed"
        echo -e "    API Base URL: ${GREEN}$API_BASE_URL${NC}"
    fi
else
    echo -e "  ⏭ API Gateway: Skipped"
fi

echo -e "\n${YELLOW}Next Steps:${NC}"
if [ "$SKIP_LAMBDAS" = false ]; then
    echo -e "  1. Build and push Lambda images to ECR:"
    echo -e "     ${GREEN}make -C backend deploy${NC}"
    echo -e "  2. Update Lambda functions to use new images"
fi
if [ "$SKIP_API_GATEWAY" = false ] && [ -n "$API_BASE_URL" ]; then
    echo -e "  3. Test API endpoints using: ${GREEN}$API_BASE_URL${NC}"
fi
echo ""

