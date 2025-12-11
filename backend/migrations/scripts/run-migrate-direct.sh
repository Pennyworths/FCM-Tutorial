#!/bin/bash
# Run Go migrate commands directly

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migration-utils.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MIGRATE_ARGS="$*"

main() {
    log "Running Go migrate: $MIGRATE_ARGS"
    check_prerequisites
    get_instance_id "$ENVIRONMENT" "$AWS_REGION"
    get_rds_endpoint "$ENVIRONMENT" "$AWS_REGION"
    get_db_credentials "$ENVIRONMENT" "$AWS_REGION"
    
    local db_url="postgres://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/$DB_NAME?sslmode=require"
    local command_id=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"cd /opt/migrations && migrate -path ./migrate -database '$db_url' $MIGRATE_ARGS\"]" \
        --query 'Command.CommandId' --output text)
    
    aws ssm wait command-executed --region "$AWS_REGION" --command-id "$command_id" --instance-id "$INSTANCE_ID"
    
    local output=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' --output text)
    
    echo "$output"
}

main "$@"
