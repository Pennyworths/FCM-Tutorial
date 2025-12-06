#!/bin/bash
# Script to get Lambda function ARNs and names for API Gateway configuration

ENVIRONMENT="${ENVIRONMENT:-cognito-test}"  # Change if your environment is different
REGION="${AWS_REGION:-us-east-1}"

echo "Getting Lambda function information for environment: $ENVIRONMENT"
echo ""

# Function names based on the naming convention in Lambdas/main.tf
FUNCTIONS=(
  "${ENVIRONMENT}-registerDeviceHandler"
  "${ENVIRONMENT}-sendMessageHandler"
  "${ENVIRONMENT}-testAckHandler"
  "${ENVIRONMENT}-testStatusHandler"
)

echo "Register Device:"
aws lambda get-function --function-name "${ENVIRONMENT}-registerDeviceHandler" --region $REGION --query 'Configuration.[FunctionArn,FunctionName]' --output text 2>/dev/null || echo "  Not found"

echo ""
echo "Send Message:"
aws lambda get-function --function-name "${ENVIRONMENT}-sendMessageHandler" --region $REGION --query 'Configuration.[FunctionArn,FunctionName]' --output text 2>/dev/null || echo "  Not found"

echo ""
echo "Test Ack:"
aws lambda get-function --function-name "${ENVIRONMENT}-testAckHandler" --region $REGION --query 'Configuration.[FunctionArn,FunctionName]' --output text 2>/dev/null || echo "  Not found"

echo ""
echo "Test Status:"
aws lambda get-function --function-name "${ENVIRONMENT}-testStatusHandler" --region $REGION --query 'Configuration.[FunctionArn,FunctionName]' --output text 2>/dev/null || echo "  Not found"

echo ""
echo "Cognito User Pool:"
aws cognito-idp list-user-pools --max-results 10 --region $REGION --query "UserPools[?contains(Name, '${ENVIRONMENT}')].{Name:Name,Id:Id,Arn:Arn}" --output table 2>/dev/null || echo "  Not found"

