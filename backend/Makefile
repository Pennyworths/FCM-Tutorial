.PHONY: help build push deploy test clean get-ecr-url lint format

# Configuration
PROJECT_ROOT := $(shell cd .. && pwd)
BACKEND_DIR := $(shell pwd)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
INFRA_LAMBDAS_DIR := $(PROJECT_ROOT)/infra/Lambdas

# Default values (only used if not set in .env file or environment)
# Note: Scripts will read from .env file, so these are just fallbacks
AWS_REGION ?= us-east-1
AWS_PROFILE ?= terraform
IMAGE_TAG ?= latest
ECR_REPO_URL ?=

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Backend Lambda Functions - Makefile Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Configuration (can be overridden with environment variables):$(NC)"
	@echo "  AWS_REGION      = $(AWS_REGION)"
	@echo "  AWS_PROFILE     = $(AWS_PROFILE)"
	@echo "  IMAGE_TAG       = $(IMAGE_TAG)"
	@echo "  ECR_REPO_URL    = $(if $(ECR_REPO_URL),$(ECR_REPO_URL),$(YELLOW)not set - use 'make get-ecr-url' or set manually$(NC))"
	@echo ""
	@echo "$(GREEN)Examples:$(NC)"
	@echo "  make get-ecr-url              # Get ECR URL from Terraform"
	@echo "  make deploy                   # Build and push all images"
	@echo "  make deploy IMAGE_TAG=v1.0.0  # Deploy with specific tag"
	@echo "  make build                    # Build images locally (no push)"

get-ecr-url: ## Get ECR repository URL from Terraform output
	@echo "$(BLUE)Getting ECR repository URL from Terraform...$(NC)"
	@cd $(INFRA_LAMBDAS_DIR) && \
		terraform output -raw ecr_repository_url 2>/dev/null || \
		(echo "$(RED)Error: Could not get ECR URL. Make sure Terraform is initialized and ECR repository exists.$(NC)" && exit 1)
	@echo "$(GREEN)✓ ECR URL retrieved$(NC)"

build: ## Build all Docker images locally (without pushing to ECR)
	@echo "$(BLUE)Building all Lambda function images locally...$(NC)"
	@ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) || \
		(echo "$(YELLOW)Warning: Could not get ECR URL from Terraform. Using placeholder...$(NC)" && \
		 ECR_REPO_URL="localhost:5000/placeholder"); \
	echo "$(BLUE)Building images with tag: $(IMAGE_TAG)$(NC)"; \
	cd $(BACKEND_DIR) && \
	for func in register-device send-message test-ack test-status; do \
		echo "$(BLUE)Building $$func...$(NC)"; \
		docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false \
			-f Lambda/API/Dockerfile -t $$ECR_REPO_URL:$$func-$(IMAGE_TAG) . || exit 1; \
	done
	@echo "$(GREEN)✓ All images built locally$(NC)"

push: ## Build and push all images to ECR
	@echo "$(BLUE)Building and pushing all Lambda function images to ECR...$(NC)"
	@ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) || \
		(echo "$(RED)Error: Could not get ECR URL. Set ECR_REPO_URL manually or run 'make get-ecr-url'$(NC)" && exit 1); \
	$(SCRIPTS_DIR)/build-and-push-backend.sh \
		--repo-url "$$ECR_REPO_URL" \
		--tag "$(IMAGE_TAG)" || \
		(echo "$(RED)Build and push failed. Make sure Docker is running and AWS credentials are configured.$(NC)" && exit 1)

update-lambdas: ## Update Lambda functions to use latest images
	@echo "$(BLUE)Updating Lambda functions to use latest images...$(NC)"
	@if [ -f $(PROJECT_ROOT)/.env ]; then \
		export $$(grep -v '^#' $(PROJECT_ROOT)/.env | xargs); \
	fi; \
	ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) || \
		(echo "$(RED)Error: Could not get ECR URL. Make sure infrastructure is deployed.$(NC)" && exit 1); \
	REGION="$${AWS_REGION:-$(AWS_REGION):-us-east-1}"; \
	PROFILE="$${AWS_PROFILE:-$(AWS_PROFILE):-terraform}"; \
	ENV="$${AWS_environment:-$(AWS_environment):-dev}"; \
	echo "$(BLUE)Environment: $$ENV, Region: $$REGION, Profile: $$PROFILE$(NC)"; \
	echo "$(BLUE)ECR Repository: $$ECR_REPO_URL$(NC)"; \
	echo ""; \
	FUNCTIONS="register-device:registerDeviceHandler send-message:sendMessageHandler test-ack:testAckHandler test-status:testStatusHandler message-ack:messageAckHandler"; \
	for func_pair in $$FUNCTIONS; do \
		func=$$(echo $$func_pair | cut -d: -f1); \
		handler=$$(echo $$func_pair | cut -d: -f2); \
		FUNC_NAME="$$ENV-$$handler"; \
		IMAGE_URI="$$ECR_REPO_URL:$$func-$(IMAGE_TAG)"; \
		echo "$(BLUE)Updating $$FUNC_NAME...$(NC)"; \
		if aws lambda update-function-code \
			--function-name "$$FUNC_NAME" \
			--image-uri "$$IMAGE_URI" \
			--region "$$REGION" \
			--profile "$$PROFILE" \
			--query '[FunctionName,LastUpdateStatus]' \
			--output text > /dev/null 2>&1; then \
			echo "$(GREEN)✓ $$FUNC_NAME updated successfully$(NC)"; \
		else \
			echo "$(YELLOW)⚠ $$FUNC_NAME update failed (function may not exist yet)$(NC)"; \
		fi; \
	done
	@echo "$(GREEN)✓ Lambda functions update complete!$(NC)"

deploy: push update-lambdas ## Build and push all images to ECR, then update Lambda functions
	@echo "$(GREEN)✓ Deployment complete!$(NC)"

# Individual function builds (for testing)
build-api: ## Build only API functions (register-device, send-message, test-ack, test-status)
	@echo "$(BLUE)Building API functions...$(NC)"
	@if [ -z "$(ECR_REPO_URL)" ]; then \
		ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) || \
		(echo "$(RED)Error: Could not get ECR URL$(NC)" && exit 1); \
	fi
	@ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) \
		IMAGE_TAG=$(IMAGE_TAG) AWS_REGION=$(AWS_REGION) AWS_PROFILE=$(AWS_PROFILE) \
		bash -c 'for func in register-device send-message test-ack test-status; do \
			echo "Building $$func..."; \
			cd $(BACKEND_DIR) && docker buildx build --platform linux/amd64 --load --provenance=false --sbom=false \
				-f Lambda/API/Dockerfile -t $$ECR_REPO_URL:$$func-$(IMAGE_TAG) . || exit 1; \
		done'

# Testing commands
test-api: ## Run tests for API functions
	@echo "$(BLUE)Running API tests...$(NC)"
	@cd Lambda/API && go test -v ./... || (echo "$(RED)Tests failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ API tests passed$(NC)"

test: test-api ## Run all tests

# Code quality
lint: ## Run linters on Go code
	@echo "$(BLUE)Running linters...$(NC)"
	@which golangci-lint > /dev/null || (echo "$(YELLOW)golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest$(NC)" && exit 1)
	@cd Lambda/API && golangci-lint run || true
	@echo "$(GREEN)✓ Linting complete$(NC)"

format: ## Format Go code
	@echo "$(BLUE)Formatting Go code...$(NC)"
	@cd Lambda/API && go fmt ./...
	@echo "$(GREEN)✓ Code formatted$(NC)"

# SQL code generation
generate-sqlc-api: ## Generate SQL code for API functions
	@echo "$(BLUE)Generating SQL code for API...$(NC)"
	@cd Lambda/API && sqlc generate || (echo "$(RED)SQL code generation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ SQL code generated for API$(NC)"

generate-sqlc: generate-sqlc-api ## Generate SQL code for all functions

# Cleanup
clean: ## Remove local Docker images
	@echo "$(BLUE)Cleaning up local Docker images...$(NC)"
	@if [ -n "$$(docker images | grep -E '(register-device|send-message|test-ack|test-status)' | awk '{print $$3}')" ]; then \
		docker rmi $$(docker images | grep -E '(register-device|send-message|test-ack|test-status)' | awk '{print $$3}') 2>/dev/null || true; \
		echo "$(GREEN)✓ Local images cleaned$(NC)"; \
	else \
		echo "$(YELLOW)No images to clean$(NC)"; \
	fi

clean-all: clean ## Remove all related Docker images and containers
	@echo "$(BLUE)Cleaning up all Docker resources...$(NC)"
	@docker system prune -f || true
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

# Development helpers
dev-setup: ## Set up development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@which go > /dev/null || (echo "$(RED)Go is not installed$(NC)" && exit 1)
	@which docker > /dev/null || (echo "$(RED)Docker is not installed$(NC)" && exit 1)
	@which sqlc > /dev/null || (echo "$(YELLOW)Installing sqlc...$(NC)" && go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest)
	@echo "$(GREEN)✓ Development environment ready$(NC)"

# Quick deploy with auto-detected ECR URL
quick-deploy: ## Quick deploy: auto-detect ECR URL and deploy with latest tag
	@echo "$(BLUE)Quick deploy: Building and pushing all images...$(NC)"
	@ECR_REPO_URL=$$(cd $(INFRA_LAMBDAS_DIR) && terraform output -raw ecr_repository_url 2>/dev/null) || \
		(echo "$(RED)Error: Could not get ECR URL. Make sure Terraform is initialized.$(NC)" && exit 1)
	@echo "$(GREEN)Using ECR URL: $$ECR_REPO_URL$(NC)"
	@ECR_REPO_URL=$$ECR_REPO_URL $(MAKE) deploy IMAGE_TAG=latest

# Show current configuration
config: ## Show current configuration
	@echo "$(BLUE)Current Configuration:$(NC)"
	@echo "  Project Root:     $(PROJECT_ROOT)"
	@echo "  Backend Dir:      $(BACKEND_DIR)"
	@echo "  Scripts Dir:      $(SCRIPTS_DIR)"
	@echo "  Infra Lambdas:    $(INFRA_LAMBDAS_DIR)"
	@echo "  AWS Region:       $(AWS_REGION)"
	@echo "  AWS Profile:      $(AWS_PROFILE)"
	@echo "  Image Tag:        $(IMAGE_TAG)"
	@if [ -z "$(ECR_REPO_URL)" ]; then \
		echo "  ECR Repo URL:     $(YELLOW)not set$(NC)"; \
		echo "  (Run 'make get-ecr-url' to get from Terraform)"; \
	else \
		echo "  ECR Repo URL:     $(GREEN)$(ECR_REPO_URL)$(NC)"; \
	fi

