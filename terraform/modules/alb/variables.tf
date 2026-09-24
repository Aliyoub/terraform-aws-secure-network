variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources."
  type        = string
}

variable "vpc_id" {
  description = "Identifiant du VPC."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets publics dans lesquels placer l'ALB (un par AZ, au moins deux requis par AWS)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security Group de l'ALB."
  type        = string
}

variable "target_instance_id" {
  description = "Instance EC2 cible du groupe de cibles."
  type        = string
}

variable "target_port" {
  description = "Port sur lequel l'application cible écoute."
  type        = number
  default     = 8080
}
