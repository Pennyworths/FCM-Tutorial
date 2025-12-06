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
      Purpose     = "Cognito User Pool"
    }
  }
}

# Local values to clean environment name for domain (cannot contain "cognito")
locals {
  # Remove "cognito" from environment name for domain (AWS doesn't allow "cognito" in domain names)
  # Remove "cognito" from environment name - handle common cases explicitly
  clean_environment = var.environment == "cognito-test" ? "test" : replace(replace(var.environment, "cognito-", ""), "cognito", "")
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-user-pool"
  
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }
  
  # Note: Standard attributes like "sub" and "email" are automatically available
  # We don't need to define them in schema blocks
  # Schema blocks are only for custom attributes, and required custom attributes are not supported
  
  username_configuration {
    case_sensitive = false
  }
  
  # Allow users to self-register
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  
  # No email verification required - users register with username only
  # account_recovery_setting is removed since we don't require email
  
  # Email configuration kept for optional email attribute (password reset, etc.)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
  
  deletion_protection = "INACTIVE"
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool"
    Description = "Cognito User Pool for FCM application authentication"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-client"
  user_pool_id = aws_cognito_user_pool.main.id
  
  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
  
  access_token_validity  = 1   # 1 hour
  id_token_validity      = 1   # 1 hour
  refresh_token_validity = 720 # 30 days (30 * 24 = 720 hours)
  
  supported_identity_providers = ["COGNITO"]
  
  callback_urls = [
    "myapp://callback"
  ]
  
  logout_urls = [
    "myapp://logout"
  ]
  
  allowed_oauth_flows = [
    "code",
    "implicit"
  ]
  
  allowed_oauth_scopes = [
    "email",
    "openid",
    "profile"
  ]
  
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

# Cognito User Pool Domain
# Note: Domain name cannot contain the reserved word "cognito"
resource "aws_cognito_user_pool_domain" "main" {
  # Domain cannot contain the reserved word "cognito"
  domain       = "fcm-${local.clean_environment}-${substr(md5(var.aws_region), 0, 8)}"
  user_pool_id = aws_cognito_user_pool.main.id
}


