#!/bin/bash
# Run migrations DOWN via SSM

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migration-utils.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
VERSION="${1:-}"

main() {
    log "Running migrations DOWN${VERSION:+ to version $VERSION}"
    check_prerequisites
    get_instance_id "$ENVIRONMENT" "$AWS_REGION"
    get_rds_endpoint "$ENVIRONMENT" "$AWS_REGION"
    get_db_credentials "$ENVIRONMENT" "$AWS_REGION"
    
    local db_url="postgres://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/$DB_NAME?sslmode=require"
    local cmd="cd /opt/migrations && migrate -path ./migrate -database '$db_url' down"
    [[ -n "$VERSION" ]] && cmd="$cmd $VERSION"
    
    local command_id=$(aws ssm send-command \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"$cmd\"]" \
        --query 'Command.CommandId' --output text)
    
    aws ssm wait command-executed --region "$AWS_REGION" --command-id "$command_id" --instance-id "$INSTANCE_ID"
    success "Migrations rolled back!"
}

main "$@"
