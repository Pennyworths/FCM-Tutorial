#!/bin/bash
# Migration Utilities Library - Simplified version for FCM-Tutorial
# Common functions shared across migration scripts

set -e

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Defaults
export DEFAULT_ENVIRONMENT="${ENVIRONMENT:-dev}"
export DEFAULT_AWS_REGION="${AWS_REGION:-us-east-1}"
export DEFAULT_PROJECT_NAME="${PROJECT_NAME:-FCM}"

# Logging
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Get script directory
get_script_paths() {
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    export PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    command -v aws &> /dev/null || { error "AWS CLI not installed"; exit 1; }
    command -v jq &> /dev/null || { error "jq not installed"; exit 1; }
    aws sts get-caller-identity &> /dev/null || { error "AWS CLI not configured"; exit 1; }
    success "Prerequisites check passed"
}

# Get EC2 instance ID by tags
get_instance_id() {
    local environment="${1:-$DEFAULT_ENVIRONMENT}"
    local aws_region="${2:-$DEFAULT_AWS_REGION}"
    local project_name="${3:-$DEFAULT_PROJECT_NAME}"
    
    if [[ -n "$INSTANCE_ID" ]]; then
        log "Using provided instance ID: $INSTANCE_ID"
        return
    fi
    
    log "Searching for migration instance..."
    INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$aws_region" \
        --filters \
            "Name=tag:Name,Values=*migration*" \
            "Name=tag:Project,Values=$project_name" \
            "Name=tag:Environment,Values=$environment" \
            "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ "$INSTANCE_ID" == "None" || -z "$INSTANCE_ID" ]]; then
        error "Could not find migration instance"
        exit 1
    fi
    
    log "Found instance ID: $INSTANCE_ID"
    export INSTANCE_ID
}

# Get RDS endpoint from Aurora cluster
get_rds_endpoint() {
    local environment="${1:-$DEFAULT_ENVIRONMENT}"
    local aws_region="${2:-$DEFAULT_AWS_REGION}"
    local project_name="${3:-$DEFAULT_PROJECT_NAME}"
    
    log "Getting RDS endpoint..."
    
    # Try Aurora clusters first
    # Match pattern: {environment}-{project_name}-cluster or {environment}-{project_name_short}-cluster
    # First try exact project name match, then try first part of project name (e.g., "fcm" from "fcm-adv")
    local project_short=$(echo "$project_name" | cut -d'-' -f1)
    local cluster_id=$(aws rds describe-db-clusters \
        --region "$aws_region" \
        --query "DBClusters[?contains(DBClusterIdentifier, '${environment}') && (contains(DBClusterIdentifier, '${project_name,,}') || contains(DBClusterIdentifier, '${project_short,,}'))].DBClusterIdentifier | [0]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$cluster_id" && "$cluster_id" != "None" ]]; then
        RDS_ENDPOINT=$(aws rds describe-db-clusters \
            --region "$aws_region" \
            --db-cluster-identifier "$cluster_id" \
            --query 'DBClusters[0].Endpoint' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$RDS_ENDPOINT" && "$RDS_ENDPOINT" != "None" ]]; then
            log "Found RDS endpoint: $RDS_ENDPOINT"
            export RDS_ENDPOINT
            export RDS_CLUSTER_ID="$cluster_id"
            return
        fi
    fi
    
    error "Could not find RDS endpoint"
    exit 1
}

# Get database credentials from Secrets Manager
get_db_credentials() {
    local environment="${1:-$DEFAULT_ENVIRONMENT}"
    local aws_region="${2:-$DEFAULT_AWS_REGION}"
    local project_name="${3:-$DEFAULT_PROJECT_NAME}"
    
    log "Getting database credentials..."
    
    # Find secret by name pattern (more reliable than tags)
    # Try multiple patterns: {env}-rds-password, {env}-{project}-rds-password, etc.
    local secret_arn=""
    
    # Pattern 1: {environment}-rds-password (e.g., dev-rds-password)
    secret_arn=$(aws secretsmanager list-secrets \
        --region "$aws_region" \
        --query "SecretList[?contains(Name, '${environment}-rds-password') || contains(Name, '${environment}-rds')].ARN | [0]" \
        --output text 2>/dev/null || echo "")
    
    # Pattern 2: If not found, try by name containing 'rds' and 'password'
    if [[ -z "$secret_arn" || "$secret_arn" == "None" ]]; then
        secret_arn=$(aws secretsmanager list-secrets \
            --region "$aws_region" \
            --query "SecretList[?contains(Name, 'rds') && contains(Name, 'password')].ARN | [0]" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "$secret_arn" || "$secret_arn" == "None" ]]; then
        error "Could not find database secret"
        exit 1
    fi
    
    local secret_value=$(aws secretsmanager get-secret-value \
        --region "$aws_region" \
        --secret-id "$secret_arn" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$secret_value" ]]; then
        error "Could not retrieve secret value"
        exit 1
    fi
    
    # Try to parse as JSON first (for structured secrets)
    local parsed_username=$(echo "$secret_value" | jq -r '.username // .user // empty' 2>/dev/null || echo "")
    local parsed_password=$(echo "$secret_value" | jq -r '.password // empty' 2>/dev/null || echo "")
    local parsed_dbname=$(echo "$secret_value" | jq -r '.dbname // .database_name // empty' 2>/dev/null || echo "")
    
    # If JSON parsing succeeded and found password, use JSON format
    if [[ -n "$parsed_password" && "$parsed_password" != "null" ]]; then
        DB_USERNAME="${parsed_username:-postgres}"
        DB_PASSWORD="$parsed_password"
        DB_NAME="${parsed_dbname:-fcm}"
    else
        # Secret is plain text password, use defaults for username and dbname
        # Try to get from RDS cluster info or use defaults
        DB_USERNAME="postgres"  # Default PostgreSQL username
        DB_PASSWORD="$secret_value"  # Use the secret value directly as password
        DB_NAME="fcmdb"  # Default database name (matches RDS default)
        
        # Try to get actual values from RDS cluster if available
        if [[ -n "$RDS_CLUSTER_ID" ]]; then
            local cluster_info=$(aws rds describe-db-clusters \
                --region "$aws_region" \
                --db-cluster-identifier "$RDS_CLUSTER_ID" \
                --query 'DBClusters[0].[MasterUsername,DatabaseName]' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$cluster_info" && "$cluster_info" != "None" ]]; then
                DB_USERNAME=$(echo "$cluster_info" | awk '{print $1}')
                DB_NAME=$(echo "$cluster_info" | awk '{print $2}')
                log "Retrieved username: $DB_USERNAME, database: $DB_NAME from RDS cluster"
            fi
        elif [[ -n "$RDS_ENDPOINT" ]]; then
            # Fallback: Extract cluster identifier from endpoint
            local cluster_id=$(echo "$RDS_ENDPOINT" | cut -d'.' -f1)
            if [[ -n "$cluster_id" ]]; then
                local cluster_info=$(aws rds describe-db-clusters \
                    --region "$aws_region" \
                    --db-cluster-identifier "$cluster_id" \
                    --query 'DBClusters[0].[MasterUsername,DatabaseName]' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$cluster_info" && "$cluster_info" != "None" ]]; then
                    DB_USERNAME=$(echo "$cluster_info" | awk '{print $1}')
                    DB_NAME=$(echo "$cluster_info" | awk '{print $2}')
                    log "Retrieved username: $DB_USERNAME, database: $DB_NAME from RDS cluster (fallback)"
                fi
            fi
        fi
    fi
    
    if [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" == "null" ]]; then
        error "Could not extract password from secret"
        exit 1
    fi
    
    log "Retrieved database credentials"
    export DB_USERNAME DB_PASSWORD DB_NAME
}

# Initialize paths
get_script_paths
