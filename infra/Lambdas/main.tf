# ============================================================================
# IMPORTANT: Deployment Order
# ============================================================================
# Lambda functions require Docker images to exist in ECR BEFORE creation.
# 
# Recommended: Use ./deploy.sh which automatically handles placeholder images.
# 
# Manual deployment flow:
# 1. Deploy this module with -target to create ECR repository first
# 2. Push placeholder or actual images to ECR
# 3. Deploy Lambda functions (images now exist)
#
# If images don't exist, Terraform will fail with:
# "ResourceInitializationError: Failed to pull image"
# ============================================================================

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
      Purpose     = "Lambda"
    }
  }
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda" {
  name = "${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-lambda-role"
  }
}

# Policy for VPC access - Required for Lambda to access RDS (via VPC)
# This allows Lambda to create ENIs in VPC and access resources like RDS
# Note: RDS access is via network (TCP), not AWS API, so no additional IAM policy needed
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Policy for CloudWatch Logs - Required for Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for Secrets Manager access - Required to read FCM credentials and RDS password
# Allows Lambda to read secrets from Secrets Manager
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.environment}-lambda-secrets-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          var.secrets_manager_secret_arn,
          var.rds_password_secret_arn
        ]
      }
    ]
  })
}

# ECR Repository for Lambda container images
resource "aws_ecr_repository" "lambda_images" {
  name                 = "${var.environment}-lambda-images"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.environment}-lambda-images"
  }
}

# ECR Lifecycle Policy - Keep last 10 images
resource "aws_ecr_lifecycle_policy" "lambda_images" {
  repository = aws_ecr_repository.lambda_images.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lambda function: registerDeviceHandler
# IMPORTANT: Before applying, ensure the ECR image exists!
# The image URI must exist in ECR before Terraform can create the Lambda function.
# Use ./deploy.sh for automated deployment (includes placeholder images), or manually push images first
resource "aws_lambda_function" "register_device" {
  function_name = "${var.environment}-registerDeviceHandler"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Container image URI from ECR
  # The image must exist in ECR before creating this Lambda function.
  # Use: ./deploy.sh (automated) or manually push images before applying
  image_uri = "${aws_ecr_repository.lambda_images.repository_url}:register-device-${var.image_tag}"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      RDS_HOST                = var.rds_host
      RDS_PORT                = tostring(var.rds_port)
      RDS_DB_NAME             = var.rds_db_name
      RDS_USERNAME            = var.rds_username
      RDS_PASSWORD_SECRET_ARN = var.rds_password_secret_arn
      SECRET_ARN              = var.secrets_manager_secret_arn
    }
  }

  tags = {
    Name = "${var.environment}-registerDeviceHandler"
  }
}

# Lambda function: sendMessageHandler
# IMPORTANT: Ensure ECR image exists before applying (see register_device function comment above)
resource "aws_lambda_function" "send_message" {
  function_name = "${var.environment}-sendMessageHandler"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Container image URI from ECR
  image_uri = "${aws_ecr_repository.lambda_images.repository_url}:send-latest"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      LAMBDA_HANDLER          = "SendMessageHandler"
      RDS_HOST                = var.rds_host
      RDS_PORT                = tostring(var.rds_port)
      RDS_DB_NAME             = var.rds_db_name
      RDS_USERNAME            = var.rds_username
      RDS_PASSWORD_SECRET_ARN = var.rds_password_secret_arn
      SECRET_ARN              = var.secrets_manager_secret_arn
    }
  }

  tags = {
    Name = "${var.environment}-sendMessageHandler"
  }
}

# Lambda function: testAckHandler
# IMPORTANT: Ensure ECR image exists before applying (see register_device function comment above)
resource "aws_lambda_function" "test_ack" {
  function_name = "${var.environment}-testAckHandler"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Container image URI from ECR - image must exist in ECR first
  image_uri = "${aws_ecr_repository.lambda_images.repository_url}:test-ack-${var.image_tag}"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      RDS_HOST                = var.rds_host
      RDS_PORT                = tostring(var.rds_port)
      RDS_DB_NAME             = var.rds_db_name
      RDS_USERNAME            = var.rds_username
      RDS_PASSWORD_SECRET_ARN = var.rds_password_secret_arn
      SECRET_ARN              = var.secrets_manager_secret_arn
    }
  }

  tags = {
    Name = "${var.environment}-testAckHandler"
  }
}

# Lambda function: testStatusHandler
# IMPORTANT: Ensure ECR image exists before applying (see register_device function comment above)
resource "aws_lambda_function" "test_status" {
  function_name = "${var.environment}-testStatusHandler"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Container image URI from ECR - image must exist in ECR first
  image_uri = "${aws_ecr_repository.lambda_images.repository_url}:test-status-${var.image_tag}"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      RDS_HOST                = var.rds_host
      RDS_PORT                = tostring(var.rds_port)
      RDS_DB_NAME             = var.rds_db_name
      RDS_USERNAME            = var.rds_username
      RDS_PASSWORD_SECRET_ARN = var.rds_password_secret_arn
      SECRET_ARN              = var.secrets_manager_secret_arn
    }
  }

  tags = {
    Name = "${var.environment}-testStatusHandler"
  }
}

# Lambda function: initSchema (for database schema initialization)
resource "aws_lambda_function" "init_schema" {
  function_name = "${var.environment}-initSchema"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  timeout       = 60  # Longer timeout for schema initialization
  memory_size   = 256

  image_uri = "${aws_ecr_repository.lambda_images.repository_url}:init-schema-${var.image_tag}"

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      RDS_HOST                = var.rds_host
      RDS_PORT                = tostring(var.rds_port)
      RDS_DB_NAME             = var.rds_db_name
      RDS_USERNAME            = var.rds_username
      RDS_PASSWORD_SECRET_ARN = var.rds_password_secret_arn
    }
  }

  tags = {
    Name = "${var.environment}-initSchema"
  }
}

