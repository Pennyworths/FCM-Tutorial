#!/bin/bash
# Run migrations UP via SSM

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migration-utils.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

main() {
    log "Running migrations UP"
    check_prerequisites
    get_instance_id "$ENVIRONMENT" "$AWS_REGION"
    get_rds_endpoint "$ENVIRONMENT" "$AWS_REGION"
    get_db_credentials "$ENVIRONMENT" "$AWS_REGION"
    
    # Upload migration files first
    log "Uploading migration files..."
    for file in migrate/*.sql; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local content=$(cat "$file" | base64 -w 0)
            aws ssm send-command \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" \
                --document-name "AWS-RunShellScript" \
                --parameters "commands=[\"echo '$content' | base64 -d > /opt/migrations/migrate/$filename\"]" \
                --query 'Command.CommandId' --output text &> /dev/null
        fi
    done
    sleep 2
    
    # Run migrations
    log "Running migrations on instance..."
    local db_url="postgres://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/$DB_NAME?sslmode=require"
    local command_id=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"cd /opt/migrations && migrate -path ./migrate -database '$db_url' up\"]" \
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
    
    if [[ -n "$output" && "$output" != "None" ]]; then
        echo "$output"
    fi
    
    if [[ "$status" == "Success" ]]; then
        success "Migrations completed!"
        exit 0
    else
        error "Migration command failed with status: $status"
        exit 1
    fi
}

main "$@"
