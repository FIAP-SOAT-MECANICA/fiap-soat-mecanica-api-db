output "db_endpoint" {
  description = "Endpoint do RDS para a aplicação se conectar"
  value       = aws_db_instance.this.endpoint
}

output "db_secret_arn" {
  description = "ARN do secret no Secrets Manager com as credenciais do banco"
  value       = aws_secretsmanager_secret.this.arn
}