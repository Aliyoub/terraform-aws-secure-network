variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources."
  type        = string
}

variable "public_subnet_id" {
  description = "Subnet public dans lequel créer le NAT Gateway (doit être routé vers un Internet Gateway)."
  type        = string
}

variable "internet_gateway_id" {
  description = "ID de l'Internet Gateway du VPC, non utilisé directement mais documente la dépendance logique (le NAT n'est utile que si l'IGW existe et route le subnet public)."
  type        = string
  default     = null
}
