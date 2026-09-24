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

# --- Phase 11 : extensions optionnelles (null/vide si désactivées) ---

output "nat_gateway_public_ip" {
  description = "IP publique du NAT Gateway, si activé."
  value       = var.enable_nat_gateway ? module.nat_gateway[0].eip_public_ip : null
}

output "vpc_endpoint_ids" {
  description = "Identifiants des VPC endpoints, si activés."
  value       = var.enable_vpc_endpoints ? module.vpc_endpoints[0].endpoint_ids : {}
}

output "ec2_demo_instance_id" {
  description = "Identifiant de l'instance EC2 de démonstration, si activée."
  value       = var.enable_ec2_demo ? module.ec2_demo[0].instance_id : null
}

output "ec2_demo_private_ip" {
  description = "IP privée de l'instance EC2 de démonstration, si activée."
  value       = var.enable_ec2_demo ? module.ec2_demo[0].private_ip : null
}

output "alb_demo_dns_name" {
  description = "Nom DNS de l'ALB de démonstration, si activé."
  value       = var.enable_alb_demo ? module.alb_demo[0].dns_name : null
}

output "rds_demo_endpoint" {
  description = "Point de terminaison de l'instance RDS de démonstration, si activée."
  value       = var.enable_rds_demo ? module.rds_demo[0].endpoint : null
}

output "flow_logs_log_group" {
  description = "Nom du groupe de logs CloudWatch pour les VPC Flow Logs, si activés."
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}
