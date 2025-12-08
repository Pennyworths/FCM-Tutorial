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
  description = "Database master password. Can be set via TF_VAR_db_password or DB_PASSWORD environment variable"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "init_schema_lambda_name" {
  description = "Name of initSchema Lambda function (optional, for automatic schema initialization)"
  type        = string
  default     = ""
}

variable "init_schema_file_path" {
  description = "Path to the database schema initialization SQL file. If empty, the module uses the default path ../../backend/Schema/init.sql relative to this module directory. Can be absolute or relative."
  type        = string
  default     = ""
}

