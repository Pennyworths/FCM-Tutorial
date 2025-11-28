output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_1_id" {
  description = "Private subnet 1 ID"
  value       = aws_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "Private subnet 2 ID"
  value       = aws_subnet.private_2.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Lambda and RDS"
  value       = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

output "lambda_security_group_id" {
  description = "Security group ID for Lambda functions"
  value       = aws_security_group.lambda.id
}
