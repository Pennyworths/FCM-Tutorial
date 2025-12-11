# Database Migrations

This directory contains database migration tools for FCM Tutorial project.

## Quick Start

### 1. Setup Environment

```bash
# Copy environment file
cp env.example .env

# Edit .env file with your AWS configuration
# AWS_PROFILE=terraform
# AWS_REGION=us-west-2
# ENVIRONMENT=dev
```

### 2. Build Docker Image

```bash
make build
# OR
./docker-migrate.sh build
```

### 3. Test Connection

```bash
make test
# OR
./docker-migrate.sh test
```

### 4. Run Migrations

```bash
make up
# OR
./docker-migrate.sh up
```

### 5. Check Status

```bash
make status
# OR
./docker-migrate.sh status
```

### 6. Connect to Database

```bash
make connect
# OR
./docker-migrate.sh connect
```

## Available Commands

### Using Makefile

```bash
make help          # Show all available commands
make build         # Build Docker image
make up            # Run migrations UP
make down          # Run migrations DOWN
make status        # Check migration status
make connect       # Connect to database
make test          # Test database connection
make shell         # Start interactive shell
make clean         # Clean up Docker resources
```

## Migration Files

Migration files are located in `migrate/` directory:

- `000001_initial_schema.up.sql` - Creates tables
- `000001_initial_schema.down.sql` - Drops tables

## How It Works

1. **Docker Container**: Provides consistent environment with all tools (Go migrate, AWS CLI, PostgreSQL client, SSM plugin)
2. **SSM Session Manager**: Securely connects to EC2 migration instance without SSH keys
3. **EC2 Migration Instance**: Runs Go migrate commands in AWS environment
4. **RDS Database**: Target database (Aurora Serverless v2) with credentials from Secrets Manager

## Architecture

```
Local Machine → Docker Container → AWS SSM → EC2 Instance → RDS Database
     ↓              ↓                ↓           ↓            ↓
  make up    →  docker-migrate.sh → SSM → Go migrate → PostgreSQL
```

## Prerequisites

- Docker and Docker Compose installed
- AWS CLI configured with appropriate credentials
- Access to AWS Secrets Manager and SSM
- Migration infrastructure deployed (EC2 instance, RDS, Secrets Manager)

## Environment Variables

Configure in `.env` file:

- `AWS_PROFILE` - AWS profile to use (default: terraform)
- `AWS_REGION` - AWS region (default: us-east-1)
- `ENVIRONMENT` - Environment name (default: dev)

## Notes

- Migration files are automatically uploaded to EC2 instance via SSM
- Database credentials are retrieved from AWS Secrets Manager
- All connections are secure via SSM Session Manager (no SSH keys needed)

