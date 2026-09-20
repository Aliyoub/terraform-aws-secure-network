output "vpc_id" {
  description = "Identifiant du VPC."
  value       = aws_vpc.this.id
}

output "cidr_block" {
  description = "Bloc CIDR du VPC."
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "Identifiant de l'Internet Gateway (null s'il n'est pas créé)."
  value       = one(aws_internet_gateway.this[*].id)
}

output "default_route_table_id" {
  description = "Identifiant de la table de routage principale du VPC (sans route)."
  value       = aws_default_route_table.this.id
}
