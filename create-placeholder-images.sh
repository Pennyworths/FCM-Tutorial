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

echo -e "${BLUE}🐳 Creating Placeholder Docker Images for Lambda${NC}"
echo -e "${BLUE}==================================================${NC}\n"

# Get ECR repository URL from Terraform
cd "$PROJECT_ROOT/infra/Lambdas"

if ! terraform output -raw ecr_repository_url > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: ECR repository not found.${NC}"
    echo -e "${YELLOW}Please deploy Lambdas module first to create ECR repository.${NC}"
    echo -e "${YELLOW}Run: cd infra/Lambdas && terraform apply${NC}"
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

# Pull AWS Lambda base image
echo -e "${BLUE}📥 Pulling AWS Lambda base image...${NC}"
docker pull public.ecr.aws/lambda/provided:al2023

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to pull base image${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Base image pulled${NC}\n"

# Create and push placeholder images for each function
FUNCTIONS=(
    "register-device"
    "send-message"
    "test-ack"
    "test-status"
)

IMAGE_TAG="${IMAGE_TAG:-latest}"

for func_tag in "${FUNCTIONS[@]}"; do
    echo -e "${BLUE}📦 Creating placeholder image for $func_tag...${NC}"
    
    # Tag the base image
    ECR_IMAGE="$ECR_REPO:$func_tag-$IMAGE_TAG"
    docker tag public.ecr.aws/lambda/provided:al2023 "$ECR_IMAGE"
    
    # Push to ECR
    echo -e "  Pushing to $ECR_IMAGE..."
    docker push "$ECR_IMAGE"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to push $ECR_IMAGE${NC}"
        exit 1
    fi
    
    # Cleanup local tag
    docker rmi "$ECR_IMAGE" 2>/dev/null || true
    
    echo -e "${GREEN}✅ $func_tag placeholder image created and pushed!${NC}"
    echo -e "   Image: $ECR_IMAGE\n"
done

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}✅ All placeholder images created successfully!${NC}"
echo -e "${GREEN}==================================================${NC}\n"

echo -e "${YELLOW}⚠️  Note:${NC}"
echo -e "  These are placeholder images using the base Lambda runtime."
echo -e "  They will work for testing infrastructure, but won't execute your Go code."
echo -e "  To deploy actual Lambda functions, build and push real images using:"
echo -e "  ./build-and-push-images.sh"
echo -e "\n"

