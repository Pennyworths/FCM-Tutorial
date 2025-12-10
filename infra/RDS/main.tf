terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# Random password for database (if not provided)
resource "random_password" "db_password" {
  count   = var.db_password == "" ? 1 : 0
  length  = 16
  special = false
}

locals {
  # Use provided password or generate random one
  db_password = var.db_password != "" ? var.db_password : try(random_password.db_password[0].result, "")
  
  # Aurora Serverless v2 capacity settings
  min_capacity = var.serverlessv2_min_capacity
  max_capacity = var.serverlessv2_max_capacity
}

# Aurora Serverless v2 Cluster (PostgreSQL)
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.environment}-${lower(var.project_name)}-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = var.engine_version
  engine_mode             = "provisioned"
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = local.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.environment}-${lower(var.project_name)}-final-snapshot"
  storage_encrypted       = true
  copy_tags_to_snapshot   = true
  delete_automated_backups = true
  enable_http_endpoint    = true  # Enable Query Editor and RDS Data API

  # Serverless v2 settings
  serverlessv2_scaling_configuration {
    min_capacity = local.min_capacity
    max_capacity = local.max_capacity
  }

  tags = {
    Name = "${var.environment}-${var.project_name}-aurora-cluster"
  }
}

# Aurora Serverless v2 Instance
resource "aws_rds_cluster_instance" "main" {
  identifier         = "${var.environment}-${lower(var.project_name)}-instance"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
  
  # Disable auto minor version upgrade to maintain IaC consistency
  auto_minor_version_upgrade = false

  tags = {
    Name = "${var.environment}-${var.project_name}-aurora-instance"
  }
}


