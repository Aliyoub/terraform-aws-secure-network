locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
}

# Phase 1 : squelette du projet uniquement. Aucune ressource AWS n'est déclarée.
# Le VPC, les subnets, le routage et les Security Groups sont ajoutés dans les phases suivantes.
