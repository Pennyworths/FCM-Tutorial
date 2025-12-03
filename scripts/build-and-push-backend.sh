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
AWS_PROFILE="${AWS_PROFILE:-terraform}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"

# ECR Repository URL (required)
ECR_REPO_URL="${ECR_REPO_URL:-}"

# Function to print usage
usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo "Options:"
    echo "  -r, --repo-url URL     ECR repository URL (required)"
    echo "  -t, --tag TAG          Docker image tag (default: latest)"
    echo "  --region REGION        AWS region (default: us-east-1)"
    echo "  --profile PROFILE      AWS profile (default: terraform)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  ECR_REPO_URL           ECR repository URL"
    echo "  IMAGE_TAG              Docker image tag"
    echo "  AWS_REGION             AWS region"
    echo "  AWS_PROFILE            AWS profile"
    echo ""
    echo "Example:"
    echo "  $0 --repo-url 793438971099.dkr.ecr.us-east-1.amazonaws.com/dev-lambda-images --tag v1.0.0"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo-url)
            ECR_REPO_URL="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
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

# Validate required parameters
if [ -z "$ECR_REPO_URL" ]; then
    echo -e "${RED}Error: ECR repository URL is required${NC}"
    echo -e "${YELLOW}Use -r/--repo-url or set ECR_REPO_URL environment variable${NC}"
    usage
fi

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Backend Lambda Functions Build & Push${NC}"
echo -e "${BLUE}===========================================${NC}\n"

echo -e "${BLUE}Configuration:${NC}"
echo -e "  ECR Repository: ${GREEN}$ECR_REPO_URL${NC}"
echo -e "  Image Tag: ${GREEN}$IMAGE_TAG${NC}"
echo -e "  AWS Region: ${GREEN}$REGION${NC}"
echo -e "  AWS Profile: ${GREEN}$AWS_PROFILE${NC}"
echo -e "  Backend Directory: ${GREEN}$BACKEND_DIR${NC}"
echo ""

# Login to ECR
echo -e "${BLUE}Logging in to ECR...${NC}"
if ! aws ecr get-login-password --region "$REGION" --profile "$AWS_PROFILE" | \
    docker login --username AWS --password-stdin "$ECR_REPO_URL"; then
    echo -e "${RED}Failed to login to ECR. Check your AWS credentials.${NC}"
    exit 1
fi
echo -e "${GREEN}Logged in to ECR${NC}\n"

# Pull base images
echo -e "${BLUE}Pulling base images...${NC}"
docker pull --platform linux/amd64 golang:1.23-alpine > /dev/null 2>&1 || true
docker pull --platform linux/amd64 public.ecr.aws/lambda/provided:al2023 > /dev/null 2>&1 || true
echo -e "${GREEN}Base images ready${NC}\n"

# Save current directory
ORIGINAL_DIR=$(pwd)

# API functions (register-device, send-message, test-ack, test-status)
# All share the same Dockerfile: backend/Lambda/API/Dockerfile
API_FUNCTIONS=(
    "register-device"
    "send-message"
    "test-ack"
    "test-status"
)

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Building API Functions${NC}"
echo -e "${BLUE}===========================================${NC}\n"

for func_tag in "${API_FUNCTIONS[@]}"; do
    ECR_IMAGE="$ECR_REPO_URL:$func_tag-$IMAGE_TAG"
    
    echo -e "${BLUE}Building $func_tag...${NC}"
    echo -e "  Image: $ECR_IMAGE"
    
    # Build from backend/ directory to access Schema/
    cd "$BACKEND_DIR"
    
    if ! docker buildx build \
        --platform linux/amd64 \
        --load \
        --provenance=false \
        --sbom=false \
        -f "Lambda/API/Dockerfile" \
        -t "$ECR_IMAGE" \
        .; then
        echo -e "${RED}Failed to build $func_tag image${NC}"
        cd "$ORIGINAL_DIR"
        exit 1
    fi
    
    # Push to ECR
    echo -e "  Pushing to ECR..."
    if ! docker push "$ECR_IMAGE"; then
        echo -e "${RED}Failed to push $ECR_IMAGE${NC}"
        cd "$ORIGINAL_DIR"
        exit 1
    fi
    
    # Cleanup local image
    docker rmi "$ECR_IMAGE" 2>/dev/null || true
    
    echo -e "${GREEN}✓ $func_tag built and pushed successfully!${NC}"
    echo -e "   Image: $ECR_IMAGE\n"
done

# init-schema function (has its own Dockerfile)
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}Building init-schema Function${NC}"
echo -e "${BLUE}===========================================${NC}\n"

INIT_SCHEMA_IMAGE="$ECR_REPO_URL:init-schema-$IMAGE_TAG"

echo -e "${BLUE}Building init-schema...${NC}"
echo -e "  Image: $INIT_SCHEMA_IMAGE"

# Build from backend/ directory to access Schema/
cd "$BACKEND_DIR"

if ! docker buildx build \
    --platform linux/amd64 \
    --load \
    --provenance=false \
    --sbom=false \
    -f "Lambda/init-schema/Dockerfile" \
    -t "$INIT_SCHEMA_IMAGE" \
    .; then
    echo -e "${RED}Failed to build init-schema image${NC}"
    cd "$ORIGINAL_DIR"
    exit 1
fi

# Push to ECR
echo -e "  Pushing to ECR..."
if ! docker push "$INIT_SCHEMA_IMAGE"; then
    echo -e "${RED}Failed to push $INIT_SCHEMA_IMAGE${NC}"
    cd "$ORIGINAL_DIR"
    exit 1
fi

# Cleanup local image
docker rmi "$INIT_SCHEMA_IMAGE" 2>/dev/null || true

echo -e "${GREEN}✓ init-schema built and pushed successfully!${NC}"
echo -e "   Image: $INIT_SCHEMA_IMAGE\n"

# Return to original directory
cd "$ORIGINAL_DIR"

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}All Backend Images Built and Pushed!${NC}"
echo -e "${GREEN}===========================================${NC}\n"

echo -e "${BLUE}Summary:${NC}"
echo -e "  API Functions (4):"
for func_tag in "${API_FUNCTIONS[@]}"; do
    echo -e "    • $func_tag: ${GREEN}$ECR_REPO_URL:$func_tag-$IMAGE_TAG${NC}"
done
echo -e "  Init Schema:"
echo -e "    • init-schema: ${GREEN}$ECR_REPO_URL:init-schema-$IMAGE_TAG${NC}"
echo ""

