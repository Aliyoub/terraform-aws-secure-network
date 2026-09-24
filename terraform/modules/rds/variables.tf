variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privés pour le groupe de subnets RDS (au moins deux AZ requises par AWS)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security Group de l'instance RDS (doit autoriser le port 5432 depuis le groupe app uniquement)."
  type        = string
}

variable "engine_version" {
  description = "Version de PostgreSQL."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Classe d'instance RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_name" {
  description = "Nom de la base de données créée au démarrage."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Nom d'utilisateur administrateur de l'instance."
  type        = string
  default     = "appadmin"
}
