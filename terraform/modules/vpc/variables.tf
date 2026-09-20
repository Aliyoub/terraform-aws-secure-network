variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources (ex. : terraform-aws-secure-network-dev)."
  type        = string
}

variable "cidr_block" {
  description = "Bloc CIDR IPv4 du VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block doit être un CIDR IPv4 valide, par exemple 10.20.0.0/16."
  }

  validation {
    condition     = can(regex("/(1[6-9]|2[0-8])$", var.cidr_block))
    error_message = "Le masque du VPC doit être compris entre /16 et /28 (limites imposées par AWS)."
  }
}

variable "enable_dns_support" {
  description = "Active la résolution DNS fournie par AWS dans le VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Attribue des noms DNS aux instances du VPC."
  type        = bool
  default     = true
}

variable "create_internet_gateway" {
  description = "Crée et attache un Internet Gateway au VPC. L'IGW seul n'expose rien : il faut aussi une route vers lui."
  type        = bool
  default     = false
}
