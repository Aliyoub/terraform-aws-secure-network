output "endpoint_ids" {
  description = "Identifiants des endpoints créés, indexés par nom de service."
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "security_group_id" {
  description = "Security Group des endpoints."
  value       = aws_security_group.endpoints.id
}
