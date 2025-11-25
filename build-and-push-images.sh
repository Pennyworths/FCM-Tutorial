#!/bin/bash
set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}🐳 Building and Pushing Docker Images to ECR${NC}"
echo -e "${BLUE}==============================================${NC}\n"

# Get ECR repository URL from Terraform
cd "$PROJECT_ROOT/infra/Lambdas"
if ! terraform output -raw ecr_repository_url > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: ECR repository not found. Please deploy Lambdas module first.${NC}"
    exit 1
fi

ECR_REPO=$(terraform output -raw ecr_repository_url)
echo -e "${GREEN}ECR Repository: $ECR_REPO${NC}\n"

# Login to ECR
echo -e "${BLUE}🔐 Logging in to ECR...${NC}"
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin $ECR_REPO

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
)

IMAGE_TAG="${IMAGE_TAG:-latest}"

for func_info in "${FUNCTIONS[@]}"; do
    IFS=':' read -r func_name source_file image_name <<< "$func_info"
    
    echo -e "${BLUE}📦 Building $func_name function...${NC}"
    
    # Compile Go code
    echo -e "  Compiling Go code..."
    GOOS=linux GOARCH=amd64 go build -o bootstrap "$source_file"
    
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
    ECR_IMAGE="$ECR_REPO:$image_name-$IMAGE_TAG"
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
    docker rmi "$image_name:$IMAGE_TAG" 2>/dev/null || true
    
    echo -e "${GREEN}✅ $func_name function built and pushed successfully!${NC}"
    echo -e "   Image: $ECR_IMAGE\n"
done

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}✅ All images built and pushed successfully!${NC}"
echo -e "${GREEN}==============================================${NC}\n"

echo -e "${YELLOW}⚠️  Next Steps:${NC}"
echo -e "  1. Update Lambda functions to use the new images:"
echo -e "     cd infra/Lambdas"
echo -e "     terraform apply -var=\"image_tag=$IMAGE_TAG\""
echo -e "\n"

