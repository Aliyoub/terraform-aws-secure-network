output "dns_name" {
  description = "Nom DNS public de l'ALB."
  value       = aws_lb.this.dns_name
}

output "arn" {
  description = "ARN de l'ALB."
  value       = aws_lb.this.arn
}
