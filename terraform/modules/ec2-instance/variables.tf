variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources."
  type        = string
}

variable "subnet_id" {
  description = "Subnet dans lequel lancer l'instance."
  type        = string
}

variable "security_group_id" {
  description = "Security Group à associer à l'instance."
  type        = string
}

variable "instance_type" {
  description = "Type d'instance EC2."
  type        = string
  default     = "t3.micro"
}

variable "user_data" {
  description = "Script cloud-init exécuté au démarrage (ex. : lancer un serveur HTTP minimal pour la démonstration ALB)."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Taille du volume racine en Go. 30 minimum pour l'AMI Amazon Linux 2023 utilisée (contrainte de son instantané, constatée à l'apply)."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "root_volume_size doit être >= 30 (contrainte de l'instantané de l'AMI Amazon Linux 2023)."
  }
}
