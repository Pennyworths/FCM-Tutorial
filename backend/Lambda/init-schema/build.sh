#!/bin/bash
set -e

# Default values
IMAGE_NAME="init-schema"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image: $FULL_IMAGE_NAME"
docker build -t "$FULL_IMAGE_NAME" .

echo ""
echo "✅ Build complete!"
echo "   Image: $FULL_IMAGE_NAME"
echo ""
echo "To push to ECR, run:"
echo "  docker tag $FULL_IMAGE_NAME <ECR_REPO_URL>:init-schema-$IMAGE_TAG"
echo "  docker push <ECR_REPO_URL>:init-schema-$IMAGE_TAG"

