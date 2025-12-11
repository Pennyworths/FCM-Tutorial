output "rds_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.main.endpoint
}

output "rds_host" {
  description = "Aurora cluster host (without port)"
  value       = split(":", aws_rds_cluster.main.endpoint)[0]
}

output "rds_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.main.port
}

output "rds_db_name" {
  description = "Aurora database name"
  value       = aws_rds_cluster.main.database_name
}

output "rds_username" {
  description = "Aurora database username"
  value       = aws_rds_cluster.main.master_username
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint (for read replicas)"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.main.arn
}

output "db_password" {
  description = "Database password (use this if password was auto-generated)"
  value       = local.db_password
  sensitive   = true
}

output "rds_security_group_id" {
  description = "RDS security group ID (for migration instance access)"
  value       = aws_security_group.rds.id
}
