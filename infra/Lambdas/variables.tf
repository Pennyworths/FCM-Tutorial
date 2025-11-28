variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "FCM"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from VPC module"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from VPC module"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Lambda security group ID from VPC module"
  type        = string
}

variable "rds_host" {
  description = "RDS host from RDS module"
  type        = string
}

variable "rds_port" {
  description = "RDS port from RDS module"
  type        = number
}

variable "rds_db_name" {
  description = "RDS database name from RDS module"
  type        = string
}

variable "rds_username" {
  description = "RDS username"
  type        = string
  sensitive   = true
}

variable "rds_password" {
  description = "RDS password"
  type        = string
  sensitive   = true
}

variable "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN for FCM credentials"
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}


variable "image_tag" {
  description = "Docker image tag for Lambda container images (e.g., 'latest', 'v1.0.0')"
  type        = string
  default     = "latest"
}

