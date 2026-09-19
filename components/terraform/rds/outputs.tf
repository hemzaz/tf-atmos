output "instance_id" {
  value       = aws_db_instance.main.id
  description = "ID of the RDS instance"
}

output "instance_address" {
  value       = aws_db_instance.main.address
  description = "Address of the RDS instance"
}

output "instance_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "Endpoint of the RDS instance"
}

output "instance_name" {
  value       = aws_db_instance.main.db_name
  description = "Name of the database"
}

output "security_group_id" {
  value       = aws_security_group.rds.id
  description = "ID of the RDS security group"
}

output "subnet_group_id" {
  value       = aws_db_subnet_group.main.id
  description = "ID of the RDS subnet group"
}

output "parameter_group_id" {
  value       = aws_db_parameter_group.main.id
  description = "ID of the RDS parameter group"
}

output "password_secret_arn" {
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
  description = "ARN of the RDS-managed Secrets Manager secret holding the master credentials"
}