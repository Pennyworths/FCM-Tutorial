output "migration_instance_id" {
  description = "EC2 instance ID for migration"
  value       = aws_instance.migration.id
}

output "migration_instance_arn" {
  description = "EC2 instance ARN for migration"
  value       = aws_instance.migration.arn
}

output "migration_security_group_id" {
  description = "Security group ID for migration instance"
  value       = aws_security_group.migration_instance.id
}

output "ssm_connect_command" {
  description = "Command to connect to migration instance via SSM"
  value       = "aws ssm start-session --target ${aws_instance.migration.id}"
}
