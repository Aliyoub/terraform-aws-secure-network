data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  # Le nombre de zones utilisées est celui de la plus longue liste de CIDR.
  az_count = max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs))
  az_names = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  # Clé courte = suffixe de la zone (a, b, c), ex. : eu-west-3a -> "a".
  public_subnets = {
    for i, cidr in var.public_subnet_cidrs :
    substr(local.az_names[i], -1, 1) => {
      cidr_block        = cidr
      availability_zone = local.az_names[i]
    }
  }

  private_subnets = {
    for i, cidr in var.private_subnet_cidrs :
    substr(local.az_names[i], -1, 1) => {
      cidr_block        = cidr
      availability_zone = local.az_names[i]
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix             = local.name_prefix
  cidr_block              = var.vpc_cidr
  create_internet_gateway = true
}

module "public_subnets" {
  source = "../../modules/subnet"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tier        = "public"
  subnets     = local.public_subnets
}

module "private_subnets" {
  source = "../../modules/subnet"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tier        = "private"
  subnets     = local.private_subnets
}

# Ce qui rend un subnet « public » : sa table de routage contient une route 0.0.0.0/0
# vers l'Internet Gateway.
module "public_route_table" {
  source = "../../modules/route-table"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tier        = "public"
  subnet_ids  = module.public_subnets.subnet_ids

  routes = {
    internet = {
      destination_cidr_block = "0.0.0.0/0"
      gateway_id             = module.vpc.internet_gateway_id
    }
  }
}

# Table privée : aucune route explicite, donc uniquement la route locale du VPC.
# Une sortie Internet (NAT Gateway, NAT instance ou endpoints) reste une option à activer
# explicitement, elle n'est jamais créée par défaut.
module "private_route_table" {
  source = "../../modules/route-table"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tier        = "private"
  subnet_ids  = module.private_subnets.subnet_ids
}

# Security Groups : chaîne alb -> app -> db. Chaque groupe n'accepte que le trafic
# du maillon précédent (référence à un groupe, pas à un CIDR) et ne sort que vers le suivant.
# Aucune règle SSH : l'administration se fait sans port entrant (voir docs/SECURITY.md).
# Les descriptions n'ont volontairement ni accents ni apostrophes (contrainte de l'API AWS).
module "alb_sg" {
  source = "../../modules/security-group"

  name_prefix = local.name_prefix
  name        = "alb"
  description = "Load balancer public optionnel - HTTPS entrant depuis les CIDR autorises"
  vpc_id      = module.vpc.vpc_id

  # Aucune règle tant que alb_allowed_https_cidrs est vide.
  ingress_rules = {
    for c in var.alb_allowed_https_cidrs : "https-${c}" => {
      description = "HTTPS entrant depuis ${c}"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = c
    }
  }

  egress_rules = {
    to-app = {
      description                  = "Trafic applicatif vers le groupe app"
      from_port                    = var.app_port
      to_port                      = var.app_port
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }
}

module "app_sg" {
  source = "../../modules/security-group"

  name_prefix = local.name_prefix
  name        = "app"
  description = "Application privee - trafic entrant uniquement depuis le groupe alb"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    from-alb = {
      description                  = "Trafic applicatif depuis le groupe alb"
      from_port                    = var.app_port
      to_port                      = var.app_port
      referenced_security_group_id = module.alb_sg.security_group_id
    }
  }

  egress_rules = {
    to-db = {
      description                  = "Acces base de donnees vers le groupe db"
      from_port                    = var.db_port
      to_port                      = var.db_port
      referenced_security_group_id = module.db_sg.security_group_id
    }
  }
}

module "db_sg" {
  source = "../../modules/security-group"

  name_prefix = local.name_prefix
  name        = "db"
  description = "Base de donnees privee - trafic entrant uniquement depuis le groupe app"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    from-app = {
      description                  = "Acces base de donnees depuis le groupe app"
      from_port                    = var.db_port
      to_port                      = var.db_port
      referenced_security_group_id = module.app_sg.security_group_id
    }
  }

  # Aucune règle sortante : la base n'initie aucune connexion.
}
