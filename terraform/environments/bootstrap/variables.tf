variable "aws_region" {
  description = "Région AWS où créer les ressources IAM. IAM est un service global : la région n'affecte que le point de terminaison de l'API, pas la portée du rôle."
  type        = string
  default     = "eu-west-3"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region doit être un nom de région AWS valide, par exemple eu-west-3."
  }
}

variable "project_name" {
  description = "Nom du projet, utilisé pour le tag Project et le nommage des ressources."
  type        = string
  default     = "terraform-aws-secure-network"
}

variable "environment" {
  description = "Environnement logique de ces ressources (distinct de dev : elles sont partagées par tous les environnements)."
  type        = string
  default     = "ci"
}

variable "owner" {
  description = "Propriétaire des ressources, utilisé pour le tag Owner."
  type        = string
  default     = "Binaté Aliyou"
}

variable "github_organization" {
  description = "Organisation ou compte GitHub propriétaire du dépôt."
  type        = string
  default     = "Aliyoub"
}

variable "github_repository" {
  description = "Nom du dépôt GitHub."
  type        = string
  default     = "terraform-aws-secure-network"
}
