variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources."
  type        = string
}

variable "vpc_id" {
  description = "Identifiant du VPC."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC, seule source autorisée à joindre les endpoints en HTTPS."
  type        = string
}

variable "region" {
  description = "Région AWS (utilisée pour construire le nom du service : com.amazonaws.<region>.<service>)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privés) dans lesquels créer les interfaces des endpoints."
  type        = list(string)
}

variable "service_names" {
  description = "Noms courts des services AWS à exposer via des Interface Endpoints (ex. : ssm, ssmmessages, ec2messages pour Session Manager)."
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages"]
}
