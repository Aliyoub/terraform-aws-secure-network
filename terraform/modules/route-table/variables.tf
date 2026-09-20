variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources (ex. : terraform-aws-secure-network-dev)."
  type        = string
}

variable "vpc_id" {
  description = "Identifiant du VPC de la table de routage."
  type        = string
}

variable "tier" {
  description = "Niveau réseau desservi, utilisé pour le nommage et le tag Tier."
  type        = string

  validation {
    condition     = contains(["public", "private"], var.tier)
    error_message = "tier doit valoir : public ou private."
  }
}

variable "subnet_ids" {
  description = "Subnets à associer à cette table, indexés par une clé courte (ex. : a, b)."
  type        = map(string)
}

variable "routes" {
  description = <<-EOT
    Routes à ajouter, indexées par un nom statique (ex. : internet). Chaque route désigne
    exactement une cible : gateway_id (Internet Gateway) ou nat_gateway_id. Laisser vide
    pour une table sans accès sortant.
  EOT
  type = map(object({
    destination_cidr_block = string
    gateway_id             = optional(string)
    nat_gateway_id         = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.routes) : can(cidrhost(r.destination_cidr_block, 0))])
    error_message = "Chaque destination_cidr_block doit être un CIDR IPv4 valide."
  }
}
