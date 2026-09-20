output "security_group_id" {
  description = "Identifiant du groupe de sécurité."
  value       = aws_security_group.this.id
}
