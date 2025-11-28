#!/bin/bash
# Quick script to check deployment status and continue from where it left off

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-terraform}"

echo -e "${BLUE}=== 检查部署状态 ===${NC}\n"

# Check Terraform states
echo -e "${BLUE}1. Terraform State 状态:${NC}"
for module in VPC RDS Secrets Lambdas API_Gateway; do
    if [ -d "$PROJECT_ROOT/infra/$module" ]; then
        cd "$PROJECT_ROOT/infra/$module"
        count=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} $module: $count 个资源"
        else
            echo -e "  ${YELLOW}○${NC} $module: 无资源"
        fi
    fi
done

echo ""
echo -e "${BLUE}2. 实际 AWS 资源:${NC}"

# Check VPC
vpcs=$(aws ec2 describe-vpcs --region us-east-1 --filters "Name=tag:Environment,Values=dev" "Name=tag:Project,Values=FCM" --query 'Vpcs[*].VpcId' --output text 2>/dev/null | wc -w)
echo -e "  VPCs: $vpcs"

# Check RDS
rds=$(aws rds describe-db-instances --region us-east-1 --query 'DBInstances[?contains(DBInstanceIdentifier, `dev`)].DBInstanceIdentifier' --output text 2>/dev/null | wc -w)
echo -e "  RDS Instances: $rds"

# Check Secrets
secrets=$(aws secretsmanager list-secrets --region us-east-1 --query 'SecretList[?contains(Name, `dev-fcm`)].Name' --output text 2>/dev/null | wc -w)
echo -e "  Secrets: $secrets"

# Check Lambda
lambdas=$(aws lambda list-functions --region us-east-1 --query 'Functions[?contains(FunctionName, `dev`)].FunctionName' --output text 2>/dev/null | wc -w)
echo -e "  Lambda Functions: $lambdas"

# Check API Gateway
apis=$(aws apigateway get-rest-apis --region us-east-1 --query 'items[?contains(name, `dev`) || contains(name, `fcm`)].name' --output text 2>/dev/null | wc -w)
echo -e "  API Gateways: $apis"

echo ""
echo -e "${GREEN}可以继续运行 ./deploy.sh${NC}"
echo -e "${YELLOW}如果遇到资源已存在的错误，Terraform 会自动同步状态${NC}"

