#!/bin/bash

# Docker Migration Wrapper Script
# This script provides easy access to migration commands via Docker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Help function
show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Docker Migration Commands:"
    echo "  shell              Start interactive shell in migration container"
    echo "  up                 Run database migrations UP"
    echo "  down [VERSION]     Run database migrations DOWN (optional version, defaults to all)"
    echo "  status             Check current migration version"
    echo "  migrate [CMD]      Run Go migrate commands directly"
    echo "  connect            Connect to database interactively"
    echo "  test               Test RDS connection"
    echo "  tables             List all database tables"
    echo "  query <name> [limit] Query data from a table (default limit: 100)"
    echo "  build              Build migration Docker image"
    echo "  logs               Show migration logs"
    echo "  clean              Clean up Docker containers and images"
    echo "  help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 shell           # Start interactive shell"
    echo "  $0 up              # Run migrations UP"
    echo "  $0 down            # Migrate down all migrations"
    echo "  $0 down 1          # Migrate down to version 1"
    echo "  $0 down 0          # Migrate down to version 0 (clean slate)"
    echo "  $0 status          # Check current migration version"
    echo "  $0 migrate version # Check current version"
    echo "  $0 migrate up      # Run migrations up"
    echo "  $0 migrate down 1  # Run migrations down by 1"
    echo "  $0 connect         # Connect to database"
    echo "  $0 test            # Test connection"
    echo "  $0 tables          # List all tables"
    echo "  $0 query devices   # Query data from 'devices' table"
    echo "  $0 query devices 10  # Query first 10 rows from 'devices' table"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_PROFILE        AWS profile to use (default: terraform)"
    echo "  AWS_REGION         AWS region (default: us-east-1)"
    echo "  ENVIRONMENT        Environment (default: dev)"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Check .env file
check_env() {
    if [[ ! -f .env ]]; then
        error ".env file not found. Please copy env.example to .env and configure it."
        exit 1
    fi
}

# Build Docker image
build_image() {
    log "Building migration Docker image..."
    docker compose build migrations
    success "Docker image built successfully"
}

# Clean up Docker resources
clean_docker() {
    log "Cleaning up Docker resources..."
    docker compose down --rmi all --volumes --remove-orphans 2>/dev/null || true
    docker system prune -f
    success "Docker cleanup completed"
}

# Main execution
main() {
    local command="${1:-help}"
    
    case $command in
        "shell")
            check_docker
            check_env
            log "Starting interactive shell in migration container..."
            docker compose run --rm migrations
            ;;
        "up")
            check_docker
            check_env
            log "Running database migrations UP..."
            docker compose run --rm run-migrations
            ;;
        "down")
            check_docker
            check_env
            local version="${2:-}"
            if [[ -n "$version" ]]; then
                log "Running database migrations DOWN to version $version..."
                docker compose run --rm migrations bash -c "./scripts/run-migrations-down.sh $version"
            else
                log "Running database migrations DOWN (all migrations)..."
                docker compose run --rm migrations bash -c "./scripts/run-migrations-down.sh"
            fi
            ;;
        "status")
            check_docker
            check_env
            log "Checking current migration version..."
            docker compose run --rm migrations bash -c "./scripts/check-migration-status.sh"
            ;;
        "migrate")
            check_docker
            check_env
            shift  # Remove "migrate" from arguments
            local migrate_args="$*"
            if [[ -z "$migrate_args" ]]; then
                migrate_args="version"
            fi
            log "Running Go migrate command: $migrate_args"
            docker compose run --rm migrations bash -c "./scripts/run-migrate-direct.sh $migrate_args"
            ;;
        "connect")
            check_docker
            check_env
            log "Connecting to database..."
            docker compose run --rm connect-db
            ;;
        "test")
            check_docker
            check_env
            log "Testing RDS connection..."
            docker compose run --rm test-connection
            ;;
        "tables")
            check_docker
            check_env
            log "Listing database tables..."
            docker compose run --rm migrations bash -c "./scripts/list-tables.sh"
            ;;
        "query")
            check_docker
            check_env
            local table_name="${2:-}"
            local limit="${3:-100}"
            if [[ -z "$table_name" ]]; then
                error "Table name required. Usage: $0 query <table_name> [limit]"
                echo "Example: $0 query devices"
                echo "Example: $0 query devices 10"
                exit 1
            fi
            log "Querying data from table: $table_name"
            docker compose run --rm migrations bash -c "./scripts/query-table.sh $table_name $limit"
            ;;
        "build")
            check_docker
            check_env
            build_image
            ;;
        "logs")
            check_docker
            log "Showing migration logs..."
            docker compose logs migrations
            ;;
        "clean")
            check_docker
            clean_docker
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

