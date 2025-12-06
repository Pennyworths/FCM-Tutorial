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
  description = "Environment name"
  type        = string
  default     = "cognito-fcm"
}

variable "fcm_service_account_json" {
  description = "FCM service account JSON content (sensitive). Can be set via TF_VAR_fcm_service_account_json or FCM_SERVICE_ACCOUNT_JSON environment variable"
  type        = string
  sensitive   = true
  default     = ""
}

variable "fcm_service_account_json_file" {
  description = "Path to FCM service account JSON file (alternative to fcm_service_account_json variable). Can be set via TF_VAR_fcm_service_account_json_file or FCM_SERVICE_ACCOUNT_JSON_FILE environment variable"
  type        = string
  default     = ""
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before it can delete the secret"
  type        = number
  default     = 30
}

variable "rds_password" {
  description = "RDS database password (sensitive). Can be set via TF_VAR_rds_password or RDS_PASSWORD/DB_PASSWORD environment variable"
  type        = string
  sensitive   = true
  default     = ""
}

