.PHONY: help deploy-all deploy-vpc deploy-rds deploy-secrets deploy-lambdas deploy-api-gateway \
        destroy destroy-vpc destroy-rds destroy-secrets destroy-lambdas destroy-api-gateway \
        plan plan-vpc plan-rds plan-secrets plan-lambdas plan-api-gateway \
        init init-vpc init-rds init-secrets init-lambdas init-api-gateway \
        output output-vpc output-rds output-secrets output-lambdas output-api-gateway \
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
	@cd VPC && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ VPC deployed$(NC)"

deploy-rds: init-rds ## Deploy RDS only (requires VPC to be deployed first)
	@echo "$(BLUE)Deploying RDS...$(NC)"
	@echo "$(YELLOW)Note: VPC must be deployed first$(NC)"
	@cd RDS && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ RDS deployed$(NC)"

deploy-secrets: init-secrets ## Deploy Secrets Manager only
	@echo "$(BLUE)Deploying Secrets Manager...$(NC)"
	@cd Secrets && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ Secrets Manager deployed$(NC)"

deploy-lambdas: init-lambdas ## Deploy Lambda functions only (requires VPC, RDS, Secrets)
	@echo "$(BLUE)Deploying Lambda functions with image tag: $(IMAGE_TAG)...$(NC)"
	@echo "$(YELLOW)Note: VPC, RDS, and Secrets must be deployed first$(NC)"
	@echo "$(YELLOW)Note: Images with tag $(IMAGE_TAG) must exist in ECR$(NC)"
	@cd Lambdas && terraform apply $(TF_AUTO_APPROVE) -var="image_tag=$(IMAGE_TAG)"
	@echo "$(GREEN)✓ Lambda functions deployed$(NC)"

deploy-api-gateway: init-api-gateway ## Deploy API Gateway only (requires Lambdas)
	@echo "$(BLUE)Deploying API Gateway...$(NC)"
	@echo "$(YELLOW)Note: Lambda functions must be deployed first$(NC)"
	@cd API_Gateway && terraform apply $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ API Gateway deployed$(NC)"

# ============================================================================
# Terraform Plan
# ============================================================================

plan: plan-vpc plan-rds plan-secrets plan-lambdas plan-api-gateway ## Plan changes for all modules

plan-vpc: init-vpc ## Plan VPC changes
	@echo "$(BLUE)Planning VPC changes...$(NC)"
	@cd VPC && terraform plan

plan-rds: init-rds ## Plan RDS changes
	@echo "$(BLUE)Planning RDS changes...$(NC)"
	@cd RDS && terraform plan

plan-secrets: init-secrets ## Plan Secrets Manager changes
	@echo "$(BLUE)Planning Secrets Manager changes...$(NC)"
	@cd Secrets && terraform plan

plan-lambdas: init-lambdas ## Plan Lambda functions changes
	@echo "$(BLUE)Planning Lambda functions changes...$(NC)"
	@cd Lambdas && terraform plan

plan-api-gateway: init-api-gateway ## Plan API Gateway changes
	@echo "$(BLUE)Planning API Gateway changes...$(NC)"
	@cd API_Gateway && terraform plan

# ============================================================================
# Terraform Init
# ============================================================================

init: init-vpc init-rds init-secrets init-lambdas init-api-gateway ## Initialize all Terraform modules

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

destroy: destroy-api-gateway destroy-lambdas destroy-secrets destroy-rds destroy-vpc ## Destroy all infrastructure (reverse order)

destroy-vpc: ## Destroy VPC (must destroy dependencies first)
	@echo "$(RED)WARNING: This will destroy VPC and all its resources!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@cd VPC && terraform destroy $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ VPC destroyed$(NC)"

destroy-rds: ## Destroy RDS
	@echo "$(RED)WARNING: This will destroy RDS instance!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@cd RDS && terraform destroy $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ RDS destroyed$(NC)"

destroy-secrets: ## Destroy Secrets Manager
	@echo "$(RED)WARNING: This will destroy secrets!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@cd Secrets && terraform destroy $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ Secrets Manager destroyed$(NC)"

destroy-lambdas: ## Destroy Lambda functions
	@echo "$(RED)WARNING: This will destroy Lambda functions!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@cd Lambdas && terraform destroy $(TF_AUTO_APPROVE)
	@echo "$(GREEN)✓ Lambda functions destroyed$(NC)"

destroy-api-gateway: ## Destroy API Gateway
	@echo "$(RED)WARNING: This will destroy API Gateway!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	@cd API_Gateway && terraform destroy $(TF_AUTO_APPROVE)
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

