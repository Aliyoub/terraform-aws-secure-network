variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources (ex. : terraform-aws-secure-network-dev)."
  type        = string
}

variable "vpc_id" {
  description = "Identifiant du VPC dans lequel créer les subnets."
  type        = string
}

variable "tier" {
  description = "Niveau réseau des subnets, utilisé pour le nommage et le tag Tier."
  type        = string

  validation {
    condition     = contains(["public", "private"], var.tier)
    error_message = "tier doit valoir : public ou private."
  }
}

variable "subnets" {
  description = "Subnets à créer, indexés par une clé courte (ex. : a, b). Chaque entrée précise son CIDR et sa zone de disponibilité."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))

  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrhost(s.cidr_block, 0))])
    error_message = "Chaque cidr_block doit être un CIDR IPv4 valide."
  }
}

variable "map_public_ip_on_launch" {
  description = "Attribue automatiquement une IP publique aux instances lancées dans ces subnets. Désactivé par défaut (moindre exposition)."
  type        = bool
  default     = false
}
