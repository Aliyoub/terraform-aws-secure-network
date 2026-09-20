variable "aws_region" {
  description = "Région AWS dans laquelle le réseau est déployé."
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
  description = "Environnement de déploiement."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment doit valoir : dev, staging ou prod."
  }
}

variable "owner" {
  description = "Propriétaire des ressources, utilisé pour le tag Owner."
  type        = string
  default     = "Binaté Aliyou"
}

variable "vpc_cidr" {
  description = "Bloc CIDR IPv4 du VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("/(1[6-9]|2[0-8])$", var.vpc_cidr))
    error_message = "vpc_cidr doit être un CIDR IPv4 valide avec un masque compris entre /16 et /28."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR des subnets publics, un par zone de disponibilité (dans l'ordre des zones)."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && length(var.public_subnet_cidrs) <= 3
    error_message = "Prévoir 2 ou 3 subnets publics afin de couvrir plusieurs zones de disponibilité."
  }

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0)) && tonumber(split("/", c)[1]) >= tonumber(split("/", var.vpc_cidr)[1]) && cidrhost(format("%s/%s", split("/", c)[0], split("/", var.vpc_cidr)[1]), 0) == cidrhost(var.vpc_cidr, 0)])
    error_message = "Chaque CIDR de subnet public doit être valide et inclus dans vpc_cidr."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR des subnets privés, un par zone de disponibilité (dans l'ordre des zones)."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2 && length(var.private_subnet_cidrs) <= 3
    error_message = "Prévoir 2 ou 3 subnets privés afin de couvrir plusieurs zones de disponibilité."
  }

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0)) && tonumber(split("/", c)[1]) >= tonumber(split("/", var.vpc_cidr)[1]) && cidrhost(format("%s/%s", split("/", c)[0], split("/", var.vpc_cidr)[1]), 0) == cidrhost(var.vpc_cidr, 0)])
    error_message = "Chaque CIDR de subnet privé doit être valide et inclus dans vpc_cidr."
  }
}

variable "app_port" {
  description = "Port TCP sur lequel l'application écoute (trafic autorisé depuis le groupe alb)."
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1024 && var.app_port <= 65535
    error_message = "app_port doit être un port non privilégié (1024 à 65535)."
  }
}

variable "db_port" {
  description = "Port TCP de la base de données (trafic autorisé depuis le groupe app). 5432 = PostgreSQL."
  type        = number
  default     = 5432

  validation {
    condition     = var.db_port >= 1 && var.db_port <= 65535
    error_message = "db_port doit être compris entre 1 et 65535."
  }
}

variable "alb_allowed_https_cidrs" {
  description = "CIDR autorisés à joindre le groupe alb en HTTPS (443). Vide par défaut : aucun accès Internet entrant. Mettre [\"0.0.0.0/0\"] uniquement pour exposer volontairement un ALB public."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.alb_allowed_https_cidrs : can(cidrhost(c, 0))])
    error_message = "Chaque entrée de alb_allowed_https_cidrs doit être un CIDR IPv4 valide."
  }
}
