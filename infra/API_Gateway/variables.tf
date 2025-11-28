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

variable "register_device_lambda_arn" {
  description = "ARN of registerDeviceHandler Lambda function (for Integration URI)"
  type        = string
}

variable "register_device_lambda_name" {
  description = "Name of registerDeviceHandler Lambda function (for Permission)"
  type        = string
}

variable "send_message_lambda_arn" {
  description = "ARN of sendMessageHandler Lambda function (for Integration URI)"
  type        = string
}

variable "send_message_lambda_name" {
  description = "Name of sendMessageHandler Lambda function (for Permission)"
  type        = string
}

variable "test_ack_lambda_arn" {
  description = "ARN of testAckHandler Lambda function (for Integration URI)"
  type        = string
}

variable "test_ack_lambda_name" {
  description = "Name of testAckHandler Lambda function (for Permission)"
  type        = string
}

variable "test_status_lambda_arn" {
  description = "ARN of testStatusHandler Lambda function (for Integration URI)"
  type        = string
}

variable "test_status_lambda_name" {
  description = "Name of testStatusHandler Lambda function (for Permission)"
  type        = string
}
