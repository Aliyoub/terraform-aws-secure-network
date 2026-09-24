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

  # Egress du groupe app : la règle vers db est permanente, les deux suivantes sont
  # ajoutées uniquement quand la démonstration correspondante est activée (Phase 11).
  app_egress_rules = merge(
    {
      to-db = {
        description                  = "Acces base de donnees vers le groupe db"
        from_port                    = var.db_port
        to_port                      = var.db_port
        referenced_security_group_id = module.db_sg.security_group_id
      }
    },
    var.enable_vpc_endpoints ? {
      to-vpc-endpoints = {
        description                  = "HTTPS vers les VPC endpoints - Session Manager"
        from_port                    = 443
        to_port                      = 443
        referenced_security_group_id = module.vpc_endpoints[0].security_group_id
      }
    } : {},
    var.enable_nat_gateway ? {
      to-internet-https = {
        description = "HTTPS sortant via NAT Gateway - test de connectivite Phase 11 uniquement"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "0.0.0.0/0"
      }
    } : {}
  )

  # Ingress de l'ALB en HTTP (80), uniquement si la démonstration ALB est activée et
  # des CIDR explicitement autorisés (même logique que alb_allowed_https_cidrs, ADR-006).
  alb_http_ingress_rules = {
    for c in var.alb_allowed_http_cidrs : "http-${c}" => {
      description = "HTTP entrant depuis ${c} - demonstration ALB Phase 11"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = c
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

# Table privée : aucune route explicite par défaut, donc uniquement la route locale du
# VPC. La route vers un NAT Gateway (Phase 11) n'est ajoutée que si enable_nat_gateway
# est activé explicitement ; elle n'est jamais créée par défaut.
module "private_route_table" {
  source = "../../modules/route-table"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  tier        = "private"
  subnet_ids  = module.private_subnets.subnet_ids

  routes = var.enable_nat_gateway ? {
    internet = {
      destination_cidr_block = "0.0.0.0/0"
      nat_gateway_id         = module.nat_gateway[0].nat_gateway_id
    }
  } : {}
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

  # Aucune règle tant que alb_allowed_https_cidrs (et alb_allowed_http_cidrs) sont vides.
  ingress_rules = merge(
    {
      for c in var.alb_allowed_https_cidrs : "https-${c}" => {
        description = "HTTPS entrant depuis ${c}"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = c
      }
    },
    local.alb_http_ingress_rules
  )

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

  egress_rules = local.app_egress_rules
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

# =============================================================================
# Phase 11 : extensions optionnelles. Rien ci-dessous n'est créé par défaut :
# chaque bloc est gardé par un interrupteur (var.enable_...) désactivé par défaut.
# Voir docs/COSTS.md pour le coût de chaque ressource.
# =============================================================================

module "nat_gateway" {
  count  = var.enable_nat_gateway ? 1 : 0
  source = "../../modules/nat-gateway"

  name_prefix         = local.name_prefix
  public_subnet_id    = module.public_subnets.subnet_ids["a"]
  internet_gateway_id = module.vpc.internet_gateway_id
}

module "vpc_endpoints" {
  count  = var.enable_vpc_endpoints ? 1 : 0
  source = "../../modules/vpc-endpoints"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = var.vpc_cidr
  region      = var.aws_region
  subnet_ids  = values(module.private_subnets.subnet_ids)
}

module "ec2_demo" {
  count  = var.enable_ec2_demo ? 1 : 0
  source = "../../modules/ec2-instance"

  name_prefix       = local.name_prefix
  subnet_id         = module.private_subnets.subnet_ids["a"]
  security_group_id = module.app_sg.security_group_id
  user_data         = <<-CLOUDINIT
    #!/bin/bash
    set -euo pipefail
    mkdir -p /srv/demo
    cat > /srv/demo/index.html <<'HTML'
    <html><body><h1>terraform-aws-secure-network</h1><p>Demonstration Phase 11 - instance dans le subnet prive.</p></body></html>
    HTML
    cd /srv/demo && nohup python3 -m http.server 8080 >/var/log/demo-http.log 2>&1 &
  CLOUDINIT
}

module "alb_demo" {
  count  = var.enable_alb_demo ? 1 : 0
  source = "../../modules/alb"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = values(module.public_subnets.subnet_ids)
  security_group_id  = module.alb_sg.security_group_id
  target_instance_id = module.ec2_demo[0].instance_id
  target_port        = var.app_port
}

module "rds_demo" {
  count  = var.enable_rds_demo ? 1 : 0
  source = "../../modules/rds"

  name_prefix       = local.name_prefix
  subnet_ids        = values(module.private_subnets.subnet_ids)
  security_group_id = module.db_sg.security_group_id
}

# VPC Flow Logs : capture tout le trafic (ALL) du VPC vers un groupe de logs dont la
# rétention est volontairement courte (1 jour), pour limiter le coût de stockage d'une
# démonstration destinée à durer quelques minutes.
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/${var.project_name}/${var.environment}/vpc-flow-logs"
  retention_in_days = 1
}

data "aws_iam_policy_document" "flow_logs_trust" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = var.enable_flow_logs ? 1 : 0
  name               = "${local.name_prefix}-flow-logs"
  description        = "Assume par le service VPC Flow Logs - ecriture dans un groupe de logs dedie uniquement"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust[0].json
}

data "aws_iam_policy_document" "flow_logs_permissions" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  name   = "${local.name_prefix}-flow-logs-policy"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_permissions[0].json
}

resource "aws_flow_log" "this" {
  count                = var.enable_flow_logs ? 1 : 0
  vpc_id               = module.vpc.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  tags = {
    Name = "${local.name_prefix}-flow-log"
  }
}
