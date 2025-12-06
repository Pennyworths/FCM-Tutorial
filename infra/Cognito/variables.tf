variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "cognito-fcm"
}

variable "environment" {
  description = "Environment name (use 'cognito-test' for independent test environment)"
  type        = string
  default     = "cognito-test"
}


