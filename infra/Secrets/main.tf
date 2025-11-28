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
      Purpose     = "Secrets"
    }
  }
}

# Determine the secret content - prefer file if provided, otherwise use variable
locals {
  # Handle file path: if relative, assume it's relative to project root (../../)
  # If absolute, use as-is
  file_path = var.fcm_service_account_json_file != "" ? (
    startswith(var.fcm_service_account_json_file, "/") ? var.fcm_service_account_json_file : (
      "${path.module}/../../${var.fcm_service_account_json_file}"
    )
  ) : ""
  
  secret_content = var.fcm_service_account_json_file != "" ? file(local.file_path) : (
    var.fcm_service_account_json != "" ? var.fcm_service_account_json : ""
  )
  
  # Validate that at least one source is provided
  secret_content_valid = local.secret_content != "" ? true : false
}

# Secrets Manager Secret for FCM credentials
resource "aws_secretsmanager_secret" "fcm_credentials" {
  name                    = "${var.environment}-fcm-credentials"
  description             = "FCM service account JSON credentials for push notifications"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name = "${var.environment}-fcm-credentials"
  }
}

# Secret version containing the FCM service account JSON
resource "aws_secretsmanager_secret_version" "fcm_credentials" {
  secret_id     = aws_secretsmanager_secret.fcm_credentials.id
  secret_string = local.secret_content

  lifecycle {
    precondition {
      condition     = local.secret_content_valid
      error_message = "Either fcm_service_account_json_file or fcm_service_account_json must be provided"
    }
  }
}

