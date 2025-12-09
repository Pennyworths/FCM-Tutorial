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
      Purpose     = "Database Migrations"
    }
  }
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for the migration EC2 instance
resource "aws_iam_role" "migration_instance" {
  name = "${var.environment}-${var.project_name}-migration-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-${var.project_name}-migration-instance-role"
  }
}

# IAM instance profile
resource "aws_iam_instance_profile" "migration_instance" {
  name = "${var.environment}-${var.project_name}-migration-instance-profile"
  role = aws_iam_role.migration_instance.name
}

# IAM policy for SSM access
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.migration_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy for Secrets Manager access
resource "aws_iam_policy" "secrets_access" {
  name        = "${var.environment}-${var.project_name}-migration-secrets-access"
  description = "Policy for migration instance to access database secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.database_secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.migration_instance.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# Security group for migration instance
resource "aws_security_group" "migration_instance" {
  name        = "${var.environment}-${var.project_name}-migration-instance-sg"
  description = "Security group for migration EC2 instance"
  vpc_id      = var.vpc_id

  # Allow outbound traffic to RDS
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]
  }

  # Allow outbound HTTPS for SSM and other AWS services
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTP for package installation
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-${var.project_name}-migration-instance-sg"
  }
}

# Update RDS security group to allow access from migration instance
resource "aws_security_group_rule" "rds_allow_migration" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.migration_instance.id
  security_group_id        = var.rds_security_group_id
  description              = "Allow migration instance to connect to RDS"
}

# CloudWatch log group for migration logs
resource "aws_cloudwatch_log_group" "migration_logs" {
  name              = "/aws/ec2/${var.environment}-${var.project_name}-migrations"
  retention_in_days = 1

  tags = {
    Name = "${var.environment}-${var.project_name}-migration-logs"
  }
}

# IAM policy for CloudWatch logging
resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${var.environment}-${var.project_name}-migration-cloudwatch-logs"
  description = "Policy for migration instance to write CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.migration_logs.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.migration_instance.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# User data script for the migration instance
locals {
  user_data = templatefile("${path.module}/user-data.sh", {
    project_name       = var.project_name
    environment        = var.environment
    log_group          = aws_cloudwatch_log_group.migration_logs.name
    database_host      = var.database_host
    database_name      = var.database_name
    database_secret_arn = var.database_secret_arn
    MIGRATE_VERSION    = "v4.16.2"
  })
}

# EC2 instance for migrations (Spot Instance for cost savings)
resource "aws_instance" "migration" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.migration_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.migration_instance.name
  user_data              = local.user_data

  # Enable public IP for SSM access
  associate_public_ip_address = true

  # Spot instance configuration (only when not using free tier)
  dynamic "instance_market_options" {
    for_each = var.use_free_tier ? [] : [1]
    content {
      market_type = "spot"
      spot_options {
        max_price = var.spot_max_price
        spot_instance_type = "one-time"
      }
    }
  }

  # Root volume configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true

    tags = {
      Name = "${var.environment}-${var.project_name}-migration-root-volume"
    }
  }

  # Disable detailed monitoring to save costs
  monitoring = false

  tags = {
    Name = "${var.environment}-${var.project_name}-migration-instance"
    SpotInstance = var.use_free_tier ? "false" : "true"
    InstanceType = var.instance_type
    InstanceMode = var.use_free_tier ? "on-demand" : "spot"
  }
}

# SSM association to ensure SSM agent is properly configured
resource "aws_ssm_association" "migration_instance" {
  name = "AWS-ConfigureAWSPackage"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.migration.id]
  }

  parameters = {
    action = "Install"
    name   = "AWSCLI"
  }

  depends_on = [aws_instance.migration]
}
