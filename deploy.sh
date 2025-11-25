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

echo -e "${BLUE}🚀 Starting FCM Infrastructure Deployment${NC}"
echo -e "${BLUE}===========================================${NC}\n"

# Function to print step
print_step() {
    echo -e "\n${GREEN}📦 Step $1: $2${NC}"
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
    
    echo -e "${GREEN}✅ $description deployed successfully!${NC}"
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
    echo -e "${RED}⚠️  Warning: terraform.tfvars may not have db_username and db_password${NC}"
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
    echo -e "${RED}⚠️  Error: service-account.json not found in project root!${NC}"
    echo -e "${YELLOW}Please ensure service-account.json exists at: $PROJECT_ROOT/service-account.json${NC}"
    exit 1
fi

terraform_apply "infra/Secrets" "Secrets Manager"

# Get Secrets output
cd "$PROJECT_ROOT/infra/Secrets"
SECRET_ARN=$(terraform output -raw secret_arn)

echo -e "${GREEN}Secrets Output:${NC}"
echo -e "  Secret ARN: $SECRET_ARN"

# Step 4: Deploy Lambdas
print_step "4" "Deploying Lambda Functions"
cd "$PROJECT_ROOT/infra/Lambdas"

# Check if terraform.tfvars exists and has RDS credentials
if [ ! -f terraform.tfvars ] || ! grep -q "rds_username" terraform.tfvars || ! grep -q "rds_password" terraform.tfvars; then
    echo -e "${RED}⚠️  Warning: terraform.tfvars may not have rds_username and rds_password${NC}"
    echo -e "${YELLOW}Please ensure infra/Lambdas/terraform.tfvars has:${NC}"
    echo -e "  rds_username = \"your_username\" (same as RDS)"
    echo -e "  rds_password = \"your_password\" (same as RDS)"
    read -p "Press Enter to continue or Ctrl+C to abort..."
fi

terraform_apply "infra/Lambdas" "Lambda Functions" \
    -var="vpc_id=$VPC_ID" \
    -var="private_subnet_ids=$PRIVATE_SUBNET_IDS" \
    -var="lambda_security_group_id=$LAMBDA_SG_ID" \
    -var="rds_host=$RDS_HOST" \
    -var="rds_port=$RDS_PORT" \
    -var="rds_db_name=$RDS_DB_NAME" \
    -var="secrets_manager_secret_arn=$SECRET_ARN"

# Get Lambda outputs
cd "$PROJECT_ROOT/infra/Lambdas"
REGISTER_DEVICE_ARN=$(terraform output -raw register_device_function_arn)
REGISTER_DEVICE_NAME=$(terraform output -raw register_device_function_name)
SEND_MESSAGE_ARN=$(terraform output -raw send_message_function_arn)
SEND_MESSAGE_NAME=$(terraform output -raw send_message_function_name)
TEST_ACK_ARN=$(terraform output -raw test_ack_function_arn)
TEST_ACK_NAME=$(terraform output -raw test_ack_function_name)
TEST_STATUS_ARN=$(terraform output -raw test_status_function_arn)
TEST_STATUS_NAME=$(terraform output -raw test_status_function_name)
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)

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
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${GREEN}===========================================${NC}\n"

echo -e "${BLUE}📋 Summary:${NC}"
echo -e "  API Base URL: ${GREEN}$API_BASE_URL${NC}"
echo -e "  ECR Repository: ${GREEN}$ECR_REPO_URL${NC}"
echo -e "  RDS Host: ${GREEN}$RDS_HOST${NC}"
echo -e "\n${YELLOW}⚠️  Next Steps:${NC}"
echo -e "  1. Build and push Docker images to ECR:"
echo -e "     ECR_REPO=$ECR_REPO_URL"
echo -e "  2. Update Lambda functions with new images"
echo -e "  3. Test API endpoints using the base URL above"
echo -e "\n"

