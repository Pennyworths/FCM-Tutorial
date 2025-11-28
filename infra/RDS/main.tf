terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Database"
    }
  }
}

# RDS Subnet Group (requires at least 2 subnets in different AZs)
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.environment}-rds-subnet-group"
  }
}

# Security Group for RDS (only Lambda can access)
resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS, allows access from Lambda"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.lambda_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-rds-sg"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier             = "${var.environment}-postgres"
  engine                 = "postgres"
  engine_version         = "15.4"  # Pin to a specific minor version for controlled upgrades
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  skip_final_snapshot = false # Set to false for production
  deletion_protection = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${var.environment}-postgres"
  }
}

# Local values for schema file path
# Defaults to standard project structure if not provided
locals {
  init_schema_file_path = var.init_schema_file_path != "" ? var.init_schema_file_path : "${path.module}/../../backend/Schema/init.sql"
}

# Database Schema Initialization
# Automatically invokes initSchema Lambda after RDS is created and available
resource "aws_lambda_invocation" "init_schema" {
  count = var.init_schema_lambda_name != "" ? 1 : 0

  function_name = var.init_schema_lambda_name

  triggers = {
    rds_endpoint = aws_db_instance.main.endpoint
    schema_hash  = filemd5(local.init_schema_file_path)
  }

  input = jsonencode({
    action = "init_schema"
  })

  depends_on = [
    aws_db_instance.main
  ]
}

