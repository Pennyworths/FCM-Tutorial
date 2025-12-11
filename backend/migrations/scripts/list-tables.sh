#!/bin/bash
# List all tables in the database

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migration-utils.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

main() {
    log "Listing database tables"
    check_prerequisites
    get_instance_id "$ENVIRONMENT" "$AWS_REGION"
    get_rds_endpoint "$ENVIRONMENT" "$AWS_REGION"
    get_db_credentials "$ENVIRONMENT" "$AWS_REGION"
    
    log "Querying tables from database..."
    local db_url="postgres://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/$DB_NAME?sslmode=require"
    local command_id=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"PGPASSWORD='$DB_PASSWORD' psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d $DB_NAME -c 'SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = '\''public'\'' ORDER BY table_name;'\"]" \
        --query 'Command.CommandId' --output text)
    
    aws ssm wait command-executed --region "$AWS_REGION" --command-id "$command_id" --instance-id "$INSTANCE_ID"
    
    local status=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'Status' --output text)
    
    local output=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' --output text)
    
    local error_output=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardErrorContent' --output text)
    
    if [[ -n "$error_output" && "$error_output" != "None" ]]; then
        echo "$error_output" >&2
    fi
    
    if [[ "$status" == "Success" ]]; then
        echo ""
        echo "$output"
        echo ""
        success "Tables listed successfully!"
        exit 0
    else
        error "Failed to list tables. Status: $status"
        if [[ -n "$output" && "$output" != "None" ]]; then
            echo "$output"
        fi
        exit 1
    fi
}

main "$@"

