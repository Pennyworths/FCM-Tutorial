#!/bin/bash
# Connect to database via SSM

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migration-utils.sh"

ENVIRONMENT="${ENVIRONMENT:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

main() {
    log "Connecting to database"
    check_prerequisites
    get_instance_id "$ENVIRONMENT" "$AWS_REGION"
    get_rds_endpoint "$ENVIRONMENT" "$AWS_REGION"
    get_db_credentials "$ENVIRONMENT" "$AWS_REGION"
    
    log "Starting SSM session to connect to database..."
    log "Instance: $INSTANCE_ID"
    log "Database: $RDS_ENDPOINT"
    
    # Use SSM Session Manager to connect interactively
    # The command will be executed on the EC2 instance to start psql
    aws ssm start-session \
        --region "$AWS_REGION" \
        --target "$INSTANCE_ID" \
        --document-name "AWS-StartInteractiveCommand" \
        --parameters "command=[\"PGPASSWORD='$DB_PASSWORD' psql -h $RDS_ENDPOINT -p 5432 -U $DB_USERNAME -d $DB_NAME\"]"
}

main "$@"
