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

output "internet_gateway_id" {
  description = "Identifiant de l'Internet Gateway."
  value       = module.vpc.internet_gateway_id
}

output "public_route_table_id" {
  description = "Identifiant de la table de routage publique (route 0.0.0.0/0 vers l'IGW)."
  value       = module.public_route_table.route_table_id
}

output "private_route_table_id" {
  description = "Identifiant de la table de routage privée (route locale uniquement)."
  value       = module.private_route_table.route_table_id
}

output "security_group_ids" {
  description = "Identifiants des groupes de sécurité, indexés par rôle."
  value = {
    alb = module.alb_sg.security_group_id
    app = module.app_sg.security_group_id
    db  = module.db_sg.security_group_id
  }
}

output "default_security_group_id" {
  description = "Groupe de sécurité par défaut du VPC (adopté, sans règle)."
  value       = module.vpc.default_security_group_id
}
