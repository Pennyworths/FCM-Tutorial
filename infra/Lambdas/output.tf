output "lambda_role_arn" {
  description = "IAM Role ARN for Lambda functions"
  value       = aws_iam_role.lambda.arn
}

output "register_device_function_arn" {
  description = "ARN of registerDeviceHandler Lambda function"
  value       = aws_lambda_function.register_device.arn
}

output "register_device_function_name" {
  description = "Name of registerDeviceHandler Lambda function"
  value       = aws_lambda_function.register_device.function_name
}

output "send_message_function_arn" {
  description = "ARN of sendMessageHandler Lambda function"
  value       = aws_lambda_function.send_message.arn
}

output "send_message_function_name" {
  description = "Name of sendMessageHandler Lambda function"
  value       = aws_lambda_function.send_message.function_name
}

output "test_ack_function_arn" {
  description = "ARN of testAckHandler Lambda function"
  value       = aws_lambda_function.test_ack.arn
}

output "test_ack_function_name" {
  description = "Name of testAckHandler Lambda function"
  value       = aws_lambda_function.test_ack.function_name
}

output "test_status_function_arn" {
  description = "ARN of testStatusHandler Lambda function"
  value       = aws_lambda_function.test_status.arn
}

output "test_status_function_name" {
  description = "Name of testStatusHandler Lambda function"
  value       = aws_lambda_function.test_status.function_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Lambda container images"
  value       = aws_ecr_repository.lambda_images.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.lambda_images.arn
}

