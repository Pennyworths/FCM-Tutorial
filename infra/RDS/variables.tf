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

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "fcmdb"
}

variable "db_username" {
  description = "Database master username. Can be set via TF_VAR_db_username or DB_USERNAME environment variable"
  type        = string
}

variable "db_password" {
  description = "Database master password. Can be set via TF_VAR_db_password or DB_PASSWORD environment variable. If empty, a random password will be generated."
  type        = string
  default     = ""
  sensitive   = true
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity (in ACU). Minimum is 0.5, maximum is 128."
  type        = number
  default     = 0.5
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity (in ACU). Minimum is 0.5, maximum is 128."
  type        = number
  default     = 1.0
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Use major version (e.g., '15') for Aurora. Can be set via TF_VAR_engine_version or ENGINE_VERSION environment variable."
  type        = string
  default     = "15"  # Aurora uses major version (e.g., 15, 14, 13)
}

