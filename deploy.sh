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

# Check if terraform.tfvars exists and has db credentials
if [ ! -f terraform.tfvars ] || ! grep -q "db_username" terraform.tfvars || ! grep -q "db_password" terraform.tfvars; then
    echo -e "${RED}Warning: terraform.tfvars may not have db_username and db_password${NC}"
    echo -e "${YELLOW}Please ensure infra/RDS/terraform.tfvars has:${NC}"
    echo -e "  db_username = \"your_username\""
    echo -e "  db_password = \"your_password\""
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

terraform_apply "infra/RDS" "RDS" \
    -var="vpc_id=$VPC_ID" \
    -var="private_subnet_ids=$PRIVATE_SUBNET_IDS" \
    -var="lambda_security_group_id=$LAMBDA_SG_ID"

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

# Check if service-account.json exists
if [ ! -f "$PROJECT_ROOT/service-account.json" ]; then
    echo -e "${RED}Error: service-account.json not found in project root!${NC}"
    echo -e "${YELLOW}Please ensure service-account.json exists at: $PROJECT_ROOT/service-account.json${NC}"
    exit 1
fi

terraform_apply "infra/Secrets" "Secrets Manager"

# Get Secrets output
cd "$PROJECT_ROOT/infra/Secrets"
SECRET_ARN=$(terraform output -raw secret_arn)

echo -e "${GREEN}Secrets Output:${NC}"
echo -e "  Secret ARN: $SECRET_ARN"

# Step 4: Deploy Lambdas (in phases to avoid image not found errors)
print_step "4a" "Creating ECR Repository and IAM Roles for Lambda"
cd "$PROJECT_ROOT/infra/Lambdas"

# Check if terraform.tfvars exists and has RDS credentials
if [ ! -f terraform.tfvars ] || ! grep -q "rds_username" terraform.tfvars || ! grep -q "rds_password" terraform.tfvars; then
    echo -e "${RED}Warning: terraform.tfvars may not have rds_username and rds_password${NC}"
    echo -e "${YELLOW}Please ensure infra/Lambdas/terraform.tfvars has:${NC}"
    echo -e "  rds_username = \"your_username\" (same as RDS)"
    echo -e "  rds_password = \"your_password\" (same as RDS)"
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

# Initialize Terraform
echo -e "${BLUE}Initializing Terraform...${NC}"
terraform init -upgrade

# Prepare terraform variables array (Terraform will auto-load terraform.tfvars for other vars)
TF_VARS=(
    "-var=vpc_id=$VPC_ID"
    "-var=private_subnet_ids=$PRIVATE_SUBNET_IDS"
    "-var=lambda_security_group_id=$LAMBDA_SG_ID"
    "-var=rds_host=$RDS_HOST"
    "-var=rds_port=$RDS_PORT"
    "-var=rds_db_name=$RDS_DB_NAME"
    "-var=secrets_manager_secret_arn=$SECRET_ARN"
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

# Step 4b: Push placeholder images to ECR
print_step "4b" "Pushing Placeholder Images to ECR"

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

# Create and push placeholder images for each function
FUNCTIONS=(
    "register-device"
    "send-message"
    "test-ack"
    "test-status"
)

IMAGE_TAG="${IMAGE_TAG:-latest}"

for func_tag in "${FUNCTIONS[@]}"; do
    echo -e "${BLUE}Creating placeholder image for $func_tag...${NC}"
    
    # Tag the base image
    ECR_IMAGE="$ECR_REPO_URL:$func_tag-$IMAGE_TAG"
    docker tag public.ecr.aws/lambda/provided:al2023 "$ECR_IMAGE"
    
    # Push to ECR
    echo -e "  Pushing to $ECR_IMAGE..."
    if ! docker push "$ECR_IMAGE"; then
        echo -e "${RED}Failed to push $ECR_IMAGE${NC}"
        exit 1
    fi
    
    # Cleanup local tag
    docker rmi "$ECR_IMAGE" 2>/dev/null || true
    
    echo -e "${GREEN}$func_tag placeholder image created and pushed!${NC}"
    echo -e "   Image: $ECR_IMAGE\n"
done

echo -e "${GREEN}All placeholder images pushed successfully${NC}\n"

# Step 4c: Deploy Lambda Functions (now that images exist in ECR)
print_step "4c" "Deploying Lambda Functions"
cd "$PROJECT_ROOT/infra/Lambdas"

echo -e "${BLUE}Creating Lambda functions (images now exist in ECR)...${NC}"
# Now apply all resources, which will create the Lambda functions
# Terraform will automatically load terraform.tfvars for rds_username and rds_password
terraform apply -auto-approve "${TF_VARS[@]}"

# Get Lambda outputs
REGISTER_DEVICE_ARN=$(terraform output -raw register_device_function_arn)
REGISTER_DEVICE_NAME=$(terraform output -raw register_device_function_name)
SEND_MESSAGE_ARN=$(terraform output -raw send_message_function_arn)
SEND_MESSAGE_NAME=$(terraform output -raw send_message_function_name)
TEST_ACK_ARN=$(terraform output -raw test_ack_function_arn)
TEST_ACK_NAME=$(terraform output -raw test_ack_function_name)
TEST_STATUS_ARN=$(terraform output -raw test_status_function_arn)
TEST_STATUS_NAME=$(terraform output -raw test_status_function_name)

echo -e "${GREEN}Lambda Functions deployed successfully!${NC}"
echo -e "${GREEN}Lambda Outputs:${NC}"
echo -e "  Register Device ARN: $REGISTER_DEVICE_ARN"
echo -e "  Send Message ARN: $SEND_MESSAGE_ARN"
echo -e "  Test Ack ARN: $TEST_ACK_ARN"
echo -e "  Test Status ARN: $TEST_STATUS_ARN"
echo -e "  ECR Repository: $ECR_REPO_URL"

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
echo -e "  1. Placeholder images have been pushed. Lambda functions are using them."
echo -e "  2. (Optional) If you have backend code, build and push actual images to ECR"
echo -e "  3. Test API endpoints using the base URL above"
echo -e "\n${BLUE}Note:${NC}"
echo -e "  Lambda functions are currently using placeholder images."
echo -e "  To deploy actual code, you'll need to build and push real images with the same names."
echo -e "\n"

