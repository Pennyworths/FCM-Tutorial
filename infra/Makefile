.PHONY: help deploy-all deploy-vpc deploy-rds deploy-secrets deploy-lambdas deploy-api-gateway deploy-migrations \
        destroy destroy-vpc destroy-rds destroy-secrets destroy-lambdas destroy-api-gateway destroy-migrations \
        plan plan-vpc plan-rds plan-secrets plan-lambdas plan-api-gateway plan-migrations \
        init init-vpc init-rds init-secrets init-lambdas init-api-gateway init-migrations \
        output output-vpc output-rds output-secrets output-lambdas output-api-gateway output-migrations \
        validate format clean get-ecr-url \
        start aws

# Configuration
PROJECT_ROOT := $(shell cd .. && pwd)
INFRA_DIR := $(shell pwd)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts

# Default values
AWS_REGION ?= us-east-1
AWS_PROFILE ?= terraform
AUTO_APPROVE ?= true
IMAGE_TAG ?= latest

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Terraform flags
TF_FLAGS := -var-file=$(PROJECT_ROOT)/.env 2>/dev/null || true
TF_AUTO_APPROVE := $(if $(filter true,$(AUTO_APPROVE)),-auto-approve,)

# Export AWS_PROFILE for Terraform
export AWS_PROFILE := $(AWS_PROFILE)

# Helper shell command to load .env and export TF_VAR_* variables
# This ensures all terraform commands use the correct region from .env
LOAD_ENV = if [ -f "$(PROJECT_ROOT)/.env" ]; then \
	set -a; \
	source "$(PROJECT_ROOT)/.env"; \
	set +a; \
	export TF_VAR_aws_region="$${AWS_REGION:-$(AWS_REGION)}"; \
	export TF_VAR_project_name="$${AWS_PROJECT:-$${AWS_project:-FCM}}"; \
	export TF_VAR_environment="$${AWS_ENVIRONMENT:-$${AWS_environment:-dev}}"; \
	export TF_VAR_db_username="$${DB_USERNAME}"; \
	export TF_VAR_db_password="$${DB_PASSWORD}"; \
	export TF_VAR_rds_username="$${RDS_USERNAME:-$${DB_USERNAME}}"; \
	export TF_VAR_rds_password="$${RDS_PASSWORD:-$${DB_PASSWORD}}"; \
	export TF_VAR_fcm_service_account_json_file="$${FCM_SERVICE_ACCOUNT_JSON_FILE}"; \
	fi;

help: ## Show this help message
	@echo "$(BLUE)Infrastructure Deployment - Makefile Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Configuration (can be overridden with environment variables):$(NC)"
	@echo "  AWS_REGION      = $(AWS_REGION)"
	@echo "  AWS_PROFILE     = $(AWS_PROFILE)"
	@echo "  IMAGE_TAG       = $(IMAGE_TAG)"
	@echo "  AUTO_APPROVE    = $(AUTO_APPROVE)"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make start                     # Configure AWS credentials"
	@echo "  make aws sts get-caller-identity  # Verify AWS credentials"
	@echo "  make deploy-all                # Deploy all infrastructure"
	@echo "  make deploy-all IMAGE_TAG=v1.0.0  # Deploy with specific image tag"
	@echo "  make deploy-vpc               # Deploy only VPC"
	@echo "  make plan                     # Plan all changes"
	@echo "  make destroy                  # Destroy all infrastructure"
	@echo "  make output                   # Show all outputs"
	@echo "  make deploy-all AUTO_APPROVE=false  # Deploy with confirmation"

# ============================================================================
# AWS CLI Setup
# ============================================================================

start: ## Configure AWS credentials
	@aws configure

aws: ## Run AWS CLI commands (e.g., make aws sts get-caller-identity)
	@aws $(filter-out $@,$(MAKECMDGOALS))

%:
	@:

# ============================================================================
# Full Deployment
# ============================================================================

deploy-all: ## Deploy all infrastructure using deploy-infra.sh script
	@echo "$(BLUE)Deploying all infrastructure...$(NC)"
	@$(SCRIPTS_DIR)/deploy-infra.sh \
		--tag $(IMAGE_TAG) \
		$(if $(filter false,$(AUTO_APPROVE)),--no-auto-approve,)

# ============================================================================
# Individual Module Deployment
# ============================================================================

deploy-vpc: init-vpc ## Deploy VPC only
	@echo "$(BLUE)Deploying VPC...$(NC)"
	@$(LOAD_ENV) cd VPC && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ VPC deployed$(NC)"

deploy-rds: init-rds ## Deploy RDS only (requires VPC to be deployed first)
	@echo "$(BLUE)Deploying RDS...$(NC)"
	@echo "$(YELLOW)Note: VPC must be deployed first$(NC)"
	@$(LOAD_ENV) cd RDS && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ RDS deployed$(NC)"

deploy-secrets: init-secrets ## Deploy Secrets Manager only
	@echo "$(BLUE)Deploying Secrets Manager...$(NC)"
	@$(LOAD_ENV) cd Secrets && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ Secrets Manager deployed$(NC)"

deploy-lambdas: init-lambdas ## Deploy Lambda functions only (requires VPC, RDS, Secrets)
	@echo "$(BLUE)Deploying Lambda functions with image tag: $(IMAGE_TAG)...$(NC)"
	@echo "$(YELLOW)Note: VPC, RDS, and Secrets must be deployed first$(NC)"
	@echo "$(YELLOW)Note: Images with tag $(IMAGE_TAG) must exist in ECR$(NC)"
	@$(LOAD_ENV) cd Lambdas && terraform apply $(TF_AUTO_APPROVE) -var="image_tag=$(IMAGE_TAG)"
	@echo "$(GREEN)✓ Lambda functions deployed$(NC)"

deploy-api-gateway: init-api-gateway ## Deploy API Gateway only (requires Lambdas)
	@echo "$(BLUE)Deploying API Gateway...$(NC)"
	@echo "$(YELLOW)Note: Lambda functions must be deployed first$(NC)"
	@$(LOAD_ENV) cd API_Gateway && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ API Gateway deployed$(NC)"

deploy-migrations: init-migrations ## Deploy Migration infrastructure only (requires VPC, RDS, Secrets)
	@echo "$(BLUE)Deploying Migration infrastructure...$(NC)"
	@echo "$(YELLOW)Note: VPC, RDS, and Secrets must be deployed first$(NC)"
	@echo "$(BLUE)Getting required values from state files...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd VPC && \
		if [ -f terraform.tfstate ]; then \
			VPC_ID=$$(jq -r '.outputs.vpc_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PUBLIC_SUBNET_ID=$$(jq -r '.outputs.public_subnet_id.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			VPC_ID="" && PUBLIC_SUBNET_ID=""; \
		fi && \
	cd ../RDS && \
		if [ -f terraform.tfstate ]; then \
			RDS_SG_ID=$$(jq -r '.outputs.rds_security_group_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_HOST=$$(jq -r '.outputs.rds_host.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_NAME=$$(jq -r '.outputs.rds_db_name.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			RDS_SG_ID="" && DATABASE_HOST="" && DATABASE_NAME=""; \
		fi && \
	cd ../Secrets && \
		if [ -f terraform.tfstate ]; then \
			DATABASE_SECRET_ARN=$$(jq -r '.outputs.rds_password_secret_arn.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			DATABASE_SECRET_ARN=""; \
		fi && \
	cd ../Migrations && \
		$(LOAD_ENV) \
		echo "$(BLUE)Deploying with values from state files...$(NC)" && \
		terraform apply $(TF_AUTO_APPROVE) \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="vpc_id=$${VPC_ID:-}" \
			-var="public_subnet_id=$${PUBLIC_SUBNET_ID:-}" \
			-var="rds_security_group_id=$${RDS_SG_ID:-}" \
			-var="database_secret_arn=$${DATABASE_SECRET_ARN:-}" \
			-var="database_host=$${DATABASE_HOST:-}" \
			-var="database_name=$${DATABASE_NAME:-}" || \
		(echo "$(RED)Deploy failed. You may need to manually check dependencies.$(NC)" && exit 1)
	@echo "$(GREEN)✓ Migration infrastructure deployed$(NC)"

# ============================================================================
# Terraform Plan
# ============================================================================

plan: plan-vpc plan-rds plan-secrets plan-lambdas plan-api-gateway plan-migrations ## Plan changes for all modules

plan-vpc: init-vpc ## Plan VPC changes
	@echo "$(BLUE)Planning VPC changes...$(NC)"
	@$(LOAD_ENV) cd VPC && terraform plan

plan-rds: init-rds ## Plan RDS changes
	@echo "$(BLUE)Planning RDS changes...$(NC)"
	@$(LOAD_ENV) cd RDS && terraform plan

plan-secrets: init-secrets ## Plan Secrets Manager changes
	@echo "$(BLUE)Planning Secrets Manager changes...$(NC)"
	@$(LOAD_ENV) cd Secrets && terraform plan

plan-lambdas: init-lambdas ## Plan Lambda functions changes
	@echo "$(BLUE)Planning Lambda functions changes...$(NC)"
	@$(LOAD_ENV) cd Lambdas && terraform plan

plan-api-gateway: init-api-gateway ## Plan API Gateway changes
	@echo "$(BLUE)Planning API Gateway changes...$(NC)"
	@$(LOAD_ENV) cd API_Gateway && terraform plan

plan-migrations: init-migrations ## Plan Migration infrastructure changes
	@echo "$(BLUE)Planning Migration infrastructure changes...$(NC)"
	@echo "$(YELLOW)Note: This requires VPC, RDS, and Secrets to be deployed first$(NC)"
	@echo "$(BLUE)Getting required values from state files...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd VPC && \
		if [ -f terraform.tfstate ]; then \
			VPC_ID=$$(jq -r '.outputs.vpc_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PUBLIC_SUBNET_ID=$$(jq -r '.outputs.public_subnet_id.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			VPC_ID="" && PUBLIC_SUBNET_ID=""; \
		fi && \
	cd ../RDS && \
		if [ -f terraform.tfstate ]; then \
			RDS_SG_ID=$$(jq -r '.outputs.rds_security_group_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_HOST=$$(jq -r '.outputs.rds_host.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_NAME=$$(jq -r '.outputs.rds_db_name.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			RDS_SG_ID="" && DATABASE_HOST="" && DATABASE_NAME=""; \
		fi && \
	cd ../Secrets && \
		if [ -f terraform.tfstate ]; then \
			DATABASE_SECRET_ARN=$$(jq -r '.outputs.rds_password_secret_arn.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			DATABASE_SECRET_ARN=""; \
		fi && \
	cd ../Migrations && \
		$(LOAD_ENV) \
		terraform plan \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="vpc_id=$${VPC_ID:-}" \
			-var="public_subnet_id=$${PUBLIC_SUBNET_ID:-}" \
			-var="rds_security_group_id=$${RDS_SG_ID:-}" \
			-var="database_secret_arn=$${DATABASE_SECRET_ARN:-}" \
			-var="database_host=$${DATABASE_HOST:-}" \
			-var="database_name=$${DATABASE_NAME:-}"

# ============================================================================
# Terraform Init
# ============================================================================

init: init-vpc init-rds init-secrets init-lambdas init-api-gateway init-migrations ## Initialize all Terraform modules

init-vpc: ## Initialize VPC Terraform module
	@echo "$(BLUE)Initializing VPC module...$(NC)"
	@cd VPC && terraform init -upgrade

init-rds: ## Initialize RDS Terraform module
	@echo "$(BLUE)Initializing RDS module...$(NC)"
	@cd RDS && terraform init -upgrade

init-secrets: ## Initialize Secrets Manager Terraform module
	@echo "$(BLUE)Initializing Secrets Manager module...$(NC)"
	@cd Secrets && terraform init -upgrade

init-lambdas: ## Initialize Lambda functions Terraform module
	@echo "$(BLUE)Initializing Lambda functions module...$(NC)"
	@cd Lambdas && terraform init -upgrade

init-api-gateway: ## Initialize API Gateway Terraform module
	@echo "$(BLUE)Initializing API Gateway module...$(NC)"
	@cd API_Gateway && terraform init -upgrade

init-migrations: ## Initialize Migrations Terraform module
	@echo "$(BLUE)Initializing Migrations module...$(NC)"
	@cd Migrations && terraform init -upgrade

# ============================================================================
# Terraform Output
# ============================================================================

output: ## Show outputs from all modules
	@echo "$(BLUE)=== VPC Outputs ===$(NC)"
	@cd VPC && terraform output 2>/dev/null || echo "No outputs"
	@echo ""
	@echo "$(BLUE)=== RDS Outputs ===$(NC)"
	@cd RDS && terraform output 2>/dev/null || echo "No outputs"
	@echo ""
	@echo "$(BLUE)=== Secrets Outputs ===$(NC)"
	@cd Secrets && terraform output 2>/dev/null || echo "No outputs"
	@echo ""
	@echo "$(BLUE)=== Lambda Outputs ===$(NC)"
	@cd Lambdas && terraform output 2>/dev/null || echo "No outputs"
	@echo ""
	@echo "$(BLUE)=== API Gateway Outputs ===$(NC)"
	@cd API_Gateway && terraform output 2>/dev/null || echo "No outputs"
	@echo ""
	@echo "$(BLUE)=== Migrations Outputs ===$(NC)"
	@cd Migrations && terraform output 2>/dev/null || echo "No outputs"

output-vpc: ## Show VPC outputs
	@cd VPC && terraform output

output-rds: ## Show RDS outputs
	@cd RDS && terraform output

output-secrets: ## Show Secrets Manager outputs
	@cd Secrets && terraform output

output-lambdas: ## Show Lambda functions outputs
	@cd Lambdas && terraform output

output-api-gateway: ## Show API Gateway outputs
	@cd API_Gateway && terraform output

output-migrations: ## Show Migration infrastructure outputs
	@cd Migrations && terraform output

get-ecr-url: ## Get ECR repository URL from Lambda outputs
	@cd Lambdas && terraform output -raw ecr_repository_url 2>/dev/null || \
		(echo "$(RED)Error: Could not get ECR URL. Make sure Lambda module is deployed.$(NC)" && exit 1)

get-vpc-id: ## Get VPC ID from VPC outputs
	@cd VPC && terraform output -raw vpc_id 2>/dev/null || \
		(echo "$(RED)Error: Could not get VPC ID. Make sure VPC module is deployed.$(NC)" && exit 1)

get-api-url: ## Get API Gateway base URL
	@cd API_Gateway && terraform output -raw api_base_url 2>/dev/null || \
		(echo "$(RED)Error: Could not get API URL. Make sure API Gateway is deployed.$(NC)" && exit 1)

# ============================================================================
# Terraform Destroy
# ============================================================================

destroy: destroy-api-gateway destroy-lambdas destroy-migrations destroy-secrets destroy-rds destroy-vpc ## Destroy all infrastructure (reverse order)

destroy-vpc: ## Destroy VPC (must destroy dependencies first)
	@echo "$(RED)WARNING: This will destroy VPC and all its resources!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	$(LOAD_ENV) cd VPC && terraform destroy $(TF_AUTO_APPROVE) -var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}"
	@echo "$(GREEN)✓ VPC destroyed$(NC)"

destroy-rds: ## Destroy RDS
	@echo "$(RED)WARNING: This will destroy RDS instance!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(BLUE)Getting required values from VPC state file...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd VPC && \
		if [ -f terraform.tfstate ]; then \
			VPC_ID=$$(jq -r '.outputs.vpc_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PRIVATE_SUBNET_1_ID=$$(jq -r '.outputs.private_subnet_1_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PRIVATE_SUBNET_2_ID=$$(jq -r '.outputs.private_subnet_2_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			LAMBDA_SG_ID=$$(jq -r '.outputs.lambda_security_group_id.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			VPC_ID="" && PRIVATE_SUBNET_1_ID="" && PRIVATE_SUBNET_2_ID="" && LAMBDA_SG_ID=""; \
		fi && \
	cd ../RDS && \
		DB_USERNAME=$$(jq -r '.outputs.rds_username.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
		$(LOAD_ENV) \
		echo "$(BLUE)Destroying with values from state files...$(NC)" && \
		terraform destroy $(TF_AUTO_APPROVE) \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="vpc_id=$${VPC_ID:-}" \
			-var="private_subnet_ids=[\"$${PRIVATE_SUBNET_1_ID:-}\",\"$${PRIVATE_SUBNET_2_ID:-}\"]" \
			-var="lambda_security_group_id=$${LAMBDA_SG_ID:-}" \
			-var="db_username=$${DB_USERNAME:-admin}" \
			-var="db_password=" || \
		(echo "$(RED)Destroy failed. You may need to manually remove RDS resources from AWS Console.$(NC)" && exit 1)
	@echo "$(GREEN)✓ RDS destroyed$(NC)"

destroy-migrations: ## Destroy Migration infrastructure
	@echo "$(RED)WARNING: This will destroy Migration infrastructure!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(BLUE)Getting required values from state files...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd VPC && \
		if [ -f terraform.tfstate ]; then \
			VPC_ID=$$(jq -r '.outputs.vpc_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PUBLIC_SUBNET_ID=$$(jq -r '.outputs.public_subnet_id.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			VPC_ID="" && PUBLIC_SUBNET_ID=""; \
		fi && \
	cd ../RDS && \
		if [ -f terraform.tfstate ]; then \
			RDS_SG_ID=$$(jq -r '.outputs.rds_security_group_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_HOST=$$(jq -r '.outputs.rds_host.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			DATABASE_NAME=$$(jq -r '.outputs.rds_db_name.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			RDS_SG_ID="" && DATABASE_HOST="" && DATABASE_NAME=""; \
		fi && \
	cd ../Secrets && \
		if [ -f terraform.tfstate ]; then \
			DATABASE_SECRET_ARN=$$(jq -r '.outputs.rds_password_secret_arn.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			DATABASE_SECRET_ARN=""; \
		fi && \
	cd ../Migrations && \
		$(LOAD_ENV) \
		echo "$(BLUE)Attempting destroy with values from state files...$(NC)" && \
		terraform destroy $(TF_AUTO_APPROVE) \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="vpc_id=$${VPC_ID:-}" \
			-var="public_subnet_id=$${PUBLIC_SUBNET_ID:-}" \
			-var="rds_security_group_id=$${RDS_SG_ID:-}" \
			-var="database_secret_arn=$${DATABASE_SECRET_ARN:-}" \
			-var="database_host=$${DATABASE_HOST:-}" \
			-var="database_name=$${DATABASE_NAME:-}" || \
		(echo "$(RED)Destroy failed. You may need to manually remove Migration resources from AWS Console.$(NC)" && exit 1)
	@echo "$(GREEN)✓ Migration infrastructure destroyed$(NC)"

destroy-secrets: ## Destroy Secrets Manager
	@echo "$(RED)WARNING: This will destroy secrets!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	$(LOAD_ENV) cd Secrets && terraform destroy $(TF_AUTO_APPROVE) -var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}"
	@echo "$(GREEN)✓ Secrets Manager destroyed$(NC)"

destroy-lambdas: ## Destroy Lambda functions
	@echo "$(RED)WARNING: This will destroy Lambda functions!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(BLUE)Getting required values from state files...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd VPC && \
		if [ -f terraform.tfstate ]; then \
			VPC_ID=$$(jq -r '.outputs.vpc_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PRIVATE_SUBNET_1_ID=$$(jq -r '.outputs.private_subnet_1_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			PRIVATE_SUBNET_2_ID=$$(jq -r '.outputs.private_subnet_2_id.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			LAMBDA_SG_ID=$$(jq -r '.outputs.lambda_security_group_id.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			VPC_ID="" && PRIVATE_SUBNET_1_ID="" && PRIVATE_SUBNET_2_ID="" && LAMBDA_SG_ID=""; \
		fi && \
	cd ../RDS && \
		if [ -f terraform.tfstate ]; then \
			RDS_HOST=$$(jq -r '.outputs.rds_host.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			RDS_PORT=$$(jq -r '.outputs.rds_port.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			RDS_DB_NAME=$$(jq -r '.outputs.rds_db_name.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			RDS_USERNAME=$$(jq -r '.outputs.rds_username.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			RDS_HOST="" && RDS_PORT="" && RDS_DB_NAME="" && RDS_USERNAME=""; \
		fi && \
	cd ../Secrets && \
		if [ -f terraform.tfstate ]; then \
			SECRET_ARN=$$(jq -r '.outputs.secret_arn.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			RDS_PASSWORD_SECRET_ARN=$$(jq -r '.outputs.rds_password_secret_arn.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			SECRET_ARN="" && RDS_PASSWORD_SECRET_ARN=""; \
		fi && \
	cd ../Lambdas && \
		ECR_REPO_URL=$$(jq -r '.outputs.ecr_repository_url.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
		if [ -n "$$ECR_REPO_URL" ]; then \
			ECR_REPO_NAME=$$(echo "$$ECR_REPO_URL" | cut -d'/' -f2) && \
			ECR_REGION=$$(echo "$$ECR_REPO_URL" | sed -n 's/.*\.dkr\.ecr\.\([^.]*\)\.amazonaws\.com.*/\1/p') && \
			if [ -z "$$ECR_REGION" ]; then ECR_REGION="$(AWS_REGION)"; fi && \
			echo "$(BLUE)Cleaning up ECR images in repository: $$ECR_REPO_NAME (region: $$ECR_REGION)...$(NC)" && \
			IMAGE_IDS_JSON=$$(aws ecr list-images --repository-name "$$ECR_REPO_NAME" --region "$$ECR_REGION" --output json 2>/dev/null || echo '{"imageIds":[]}') && \
			IMAGE_COUNT=$$(echo "$$IMAGE_IDS_JSON" | jq -r '.imageIds | length' 2>/dev/null || echo "0") && \
			if [ "$$IMAGE_COUNT" -gt 0 ]; then \
				echo "$(YELLOW)Found $$IMAGE_COUNT image(s), deleting...$(NC)" && \
				TMP_FILE=$$(mktemp) && \
				echo "$$IMAGE_IDS_JSON" | jq '{imageIds: .imageIds}' > "$$TMP_FILE" && \
				aws ecr batch-delete-image --repository-name "$$ECR_REPO_NAME" --region "$$ECR_REGION" --cli-input-json "file://$$TMP_FILE" >/dev/null 2>&1 || true && \
				rm -f "$$TMP_FILE" && \
				echo "$(GREEN)ECR images cleaned up$(NC)"; \
			else \
				echo "$(GREEN)ECR repository is already empty$(NC)"; \
			fi; \
		fi && \
		$(LOAD_ENV) \
		echo "$(BLUE)Destroying with values from state files...$(NC)" && \
		terraform destroy $(TF_AUTO_APPROVE) \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="vpc_id=$${VPC_ID:-}" \
			-var="private_subnet_ids=[\"$${PRIVATE_SUBNET_1_ID:-}\",\"$${PRIVATE_SUBNET_2_ID:-}\"]" \
			-var="lambda_security_group_id=$${LAMBDA_SG_ID:-}" \
			-var="rds_host=$${RDS_HOST:-}" \
			-var="rds_port=$${RDS_PORT:-}" \
			-var="rds_db_name=$${RDS_DB_NAME:-}" \
			-var="rds_username=$${RDS_USERNAME:-}" \
			-var="secrets_manager_secret_arn=$${SECRET_ARN:-}" \
			-var="rds_password_secret_arn=$${RDS_PASSWORD_SECRET_ARN:-}" || \
		(echo "$(RED)Destroy failed. You may need to manually remove Lambda resources from AWS Console.$(NC)" && exit 1)
	@echo "$(GREEN)✓ Lambda functions destroyed$(NC)"

destroy-api-gateway: ## Destroy API Gateway
	@echo "$(RED)WARNING: This will destroy API Gateway!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@echo "$(BLUE)Getting Lambda ARNs from Lambdas state file...$(NC)"
	@export AWS_PROFILE="$(AWS_PROFILE)" && \
	cd Lambdas && \
		if [ -f terraform.tfstate ]; then \
			REGISTER_DEVICE_ARN=$$(jq -r '.outputs.register_device_function_arn.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			REGISTER_DEVICE_NAME=$$(jq -r '.outputs.register_device_function_name.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			SEND_MESSAGE_ARN=$$(jq -r '.outputs.send_message_function_arn.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			SEND_MESSAGE_NAME=$$(jq -r '.outputs.send_message_function_name.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			TEST_ACK_ARN=$$(jq -r '.outputs.test_ack_function_arn.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			TEST_ACK_NAME=$$(jq -r '.outputs.test_ack_function_name.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			TEST_STATUS_ARN=$$(jq -r '.outputs.test_status_function_arn.value // empty' terraform.tfstate 2>/dev/null || echo "") && \
			TEST_STATUS_NAME=$$(jq -r '.outputs.test_status_function_name.value // empty' terraform.tfstate 2>/dev/null || echo ""); \
		else \
			REGISTER_DEVICE_ARN="" && \
			REGISTER_DEVICE_NAME="" && \
			SEND_MESSAGE_ARN="" && \
			SEND_MESSAGE_NAME="" && \
			TEST_ACK_ARN="" && \
			TEST_ACK_NAME="" && \
			TEST_STATUS_ARN="" && \
			TEST_STATUS_NAME=""; \
		fi && \
		cd ../API_Gateway && \
		$(LOAD_ENV) \
		echo "$(BLUE)Destroying with Lambda ARNs from state file...$(NC)" && \
		terraform destroy $(TF_AUTO_APPROVE) \
			-var="aws_region=$${TF_VAR_aws_region:-$(AWS_REGION)}" \
			-var="register_device_lambda_arn=$${REGISTER_DEVICE_ARN:-dummy}" \
			-var="register_device_lambda_name=$${REGISTER_DEVICE_NAME:-dummy}" \
			-var="send_message_lambda_arn=$${SEND_MESSAGE_ARN:-dummy}" \
			-var="send_message_lambda_name=$${SEND_MESSAGE_NAME:-dummy}" \
			-var="test_ack_lambda_arn=$${TEST_ACK_ARN:-dummy}" \
			-var="test_ack_lambda_name=$${TEST_ACK_NAME:-dummy}" \
			-var="test_status_lambda_arn=$${TEST_STATUS_ARN:-dummy}" \
			-var="test_status_lambda_name=$${TEST_STATUS_NAME:-dummy}" || \
		(echo "$(RED)Destroy failed. You may need to manually remove API Gateway resources from AWS Console.$(NC)" && exit 1)
	@echo "$(GREEN)✓ API Gateway destroyed$(NC)"

# ============================================================================
# Terraform Validation and Formatting
# ============================================================================

validate: ## Validate all Terraform configurations
	@echo "$(BLUE)Validating Terraform configurations...$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		echo "$(BLUE)Validating $$dir...$(NC)"; \
		cd $$dir && terraform init -upgrade > /dev/null 2>&1 && terraform validate || \
			(echo "$(RED)Validation failed for $$dir$(NC)" && exit 1); \
		cd ..; \
	done
	@echo "$(GREEN)✓ All configurations are valid$(NC)"

format: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		echo "$(BLUE)Formatting $$dir...$(NC)"; \
		cd $$dir && terraform fmt -recursive; \
		cd ..; \
	done
	@echo "$(GREEN)✓ All files formatted$(NC)"

format-check: ## Check if Terraform files are formatted
	@echo "$(BLUE)Checking Terraform file formatting...$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		cd $$dir && terraform fmt -check -recursive || \
			(echo "$(RED)Files in $$dir are not formatted$(NC)" && exit 1); \
		cd ..; \
	done
	@echo "$(GREEN)✓ All files are properly formatted$(NC)"

# ============================================================================
# State Management
# ============================================================================

refresh: ## Refresh Terraform state for all modules
	@echo "$(BLUE)Refreshing Terraform state...$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		echo "$(BLUE)Refreshing $$dir...$(NC)"; \
		cd $$dir && terraform refresh -auto-approve > /dev/null 2>&1 || true; \
		cd ..; \
	done
	@echo "$(GREEN)✓ State refreshed$(NC)"

show: ## Show current Terraform state (all modules)
	@echo "$(BLUE)Showing Terraform state...$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		echo "$(BLUE)=== $$dir ===$(NC)"; \
		cd $$dir && terraform show 2>/dev/null | head -20 || echo "No state"; \
		cd ..; \
		echo ""; \
	done

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Remove Terraform state files and .terraform directories (DANGEROUS!)
	@echo "$(RED)WARNING: This will remove all Terraform state files!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		echo "$(BLUE)Cleaning $$dir...$(NC)"; \
		cd $$dir && rm -rf .terraform terraform.tfstate* .terraform.lock.hcl 2>/dev/null || true; \
		cd ..; \
	done
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

# ============================================================================
# Configuration
# ============================================================================

config: ## Show current configuration
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo "  Project Root:      $(PROJECT_ROOT)"
	@echo "  Infra Dir:         $(INFRA_DIR)"
	@echo "  Scripts Dir:       $(SCRIPTS_DIR)"
	@echo "  AWS Region:        $(AWS_REGION)"
	@echo "  AWS Profile:       $(AWS_PROFILE)"
	@echo "  Image Tag:         $(IMAGE_TAG)"
	@echo "  Auto Approve:      $(AUTO_APPROVE)"
	@echo ""
	@echo "$(BLUE)Module Status:$(NC)"
	@for dir in VPC RDS Secrets Lambdas API_Gateway; do \
		if [ -f "$$dir/terraform.tfstate" ]; then \
			echo "  $$dir: $(GREEN)deployed$(NC)"; \
		else \
			echo "  $$dir: $(YELLOW)not deployed$(NC)"; \
		fi; \
	done

