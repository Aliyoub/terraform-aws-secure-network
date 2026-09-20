output "aws_region" {
  description = "Région ciblée par cet environnement."
  value       = var.aws_region
}

output "tags" {
  description = "Tags appliqués par défaut à toutes les ressources."
  value       = local.tags
}

output "vpc_id" {
  description = "Identifiant du VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Bloc CIDR du VPC."
  value       = module.vpc.cidr_block
}

output "public_subnet_ids" {
  description = "Identifiants des subnets publics, indexés par zone (a, b, ...)."
  value       = module.public_subnets.subnet_ids
}

output "private_subnet_ids" {
  description = "Identifiants des subnets privés, indexés par zone (a, b, ...)."
  value       = module.private_subnets.subnet_ids
}

output "availability_zones" {
  description = "Zones de disponibilité utilisées."
  value       = local.az_names
}
