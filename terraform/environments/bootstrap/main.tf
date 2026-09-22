locals {
  name_prefix = var.project_name

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  # Actions en lecture seule nécessaires pour que "terraform plan" évalue les ressources
  # réseau actuellement définies (modules vpc, subnet, route-table, security-group).
  # Étendre cette liste au fur et à mesure des ressources ajoutées, jamais par anticipation :
  # aucune action de création, modification ou suppression ne doit y figurer (ADR-016).
  plan_read_only_actions = [
    "ec2:DescribeVpcs",
    "ec2:DescribeVpcAttribute",
    "ec2:DescribeSubnets",
    "ec2:DescribeRouteTables",
    "ec2:DescribeInternetGateways",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSecurityGroupRules",
    "ec2:DescribeNetworkAcls",
    "ec2:DescribeAvailabilityZones",
    "ec2:DescribeTags",
  ]
}

# Rôle assumé par le workflow terraform-plan (Phase 7/8) : peut lire l'état réel du
# compte pour produire un plan fidèle, ne peut rien créer, modifier ni supprimer.
# Autorisé depuis les pull requests (revue avant fusion) et les push sur main.
module "github_actions_plan_role" {
  source = "../../modules/github-oidc"

  name_prefix = local.name_prefix

  github_organization = var.github_organization
  github_repository   = var.github_repository
  allowed_branches    = ["main"]
  allow_pull_requests = true

  role_purpose      = "plan"
  role_description  = "Assume par GitHub Actions via OIDC - lecture seule pour terraform plan, aucun apply"
  read_only_actions = local.plan_read_only_actions
}
