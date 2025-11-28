output "secret_arn" {
  description = "ARN of the FCM credentials secret"
  value       = aws_secretsmanager_secret.fcm_credentials.arn
}

output "secret_name" {
  description = "Name of the FCM credentials secret"
  value       = aws_secretsmanager_secret.fcm_credentials.name
}

output "secret_id" {
  description = "ID of the FCM credentials secret"
  value       = aws_secretsmanager_secret.fcm_credentials.id
}

output "rds_password_secret_arn" {
  description = "ARN of the RDS password secret"
  value       = aws_secretsmanager_secret.rds_password.arn
}

output "rds_password_secret_name" {
  description = "Name of the RDS password secret"
  value       = aws_secretsmanager_secret.rds_password.name
}

