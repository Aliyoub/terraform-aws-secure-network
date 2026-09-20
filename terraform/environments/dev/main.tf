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
