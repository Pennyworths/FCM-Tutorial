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

variable "public_subnet_id" {
  description = "Public subnet ID from VPC module (for migration instance)"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID from RDS module"
  type        = string
}

variable "database_secret_arn" {
  description = "RDS password secret ARN from Secrets Manager"
  type        = string
}

variable "database_host" {
  description = "RDS database host from RDS module"
  type        = string
}

variable "database_name" {
  description = "Database name from RDS module"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for migration instance"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 8
}

variable "spot_max_price" {
  description = "Maximum price for spot instance (in USD per hour)"
  type        = string
  default     = "0.01"
}

variable "use_free_tier" {
  description = "Use AWS Free Tier eligible instance types (t3.micro) instead of spot instances"
  type        = bool
  default     = false
}
