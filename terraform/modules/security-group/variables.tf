variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources (ex. : terraform-aws-secure-network-dev)."
  type        = string
}

variable "name" {
  description = "Rôle du groupe de sécurité (ex. : alb, app, db), utilisé dans son nom et le tag Role."
  type        = string
}

variable "description" {
  description = "Description du groupe. AWS n'accepte ni accents ni apostrophes : a-z A-Z 0-9 et . _-:/()#,@[]+=&;{}!$* uniquement."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9. _:/()#,@+=&;{}!$*\\[\\]-]+$", var.description))
    error_message = "La description ne doit contenir que des caractères acceptés par AWS (pas d'accents ni d'apostrophes)."
  }
}

variable "vpc_id" {
  description = "Identifiant du VPC du groupe de sécurité."
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Règles entrantes, indexées par un nom statique. Chaque règle désigne exactement une source :
    cidr_ipv4 OU referenced_security_group_id. Préférer une référence à un autre groupe de sécurité
    plutôt qu'un CIDR. Les ports sont laissés à null uniquement pour protocol = "-1" (interdit en entrée).
  EOT
  type = map(object({
    description                  = string
    from_port                    = number
    to_port                      = number
    protocol                     = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.ingress_rules) :
      can(regex("^[a-zA-Z0-9. _:/()#,@+=&;{}!$*\\[\\]-]+$", r.description))
    ])
    error_message = "Chaque description de règle ne doit contenir que des caractères acceptés par AWS (pas d'accents ni d'apostrophes)."
  }

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : r.protocol != "-1"])
    error_message = "Une règle entrante « tous protocoles » (-1) est interdite : préciser un protocole et un port."
  }

  validation {
    condition = alltrue([
      for r in values(var.ingress_rules) :
      r.from_port >= 0 && r.to_port <= 65535 && r.from_port <= r.to_port
    ])
    error_message = "from_port et to_port doivent être compris entre 0 et 65535, avec from_port <= to_port."
  }

  validation {
    condition = alltrue([
      for r in values(var.ingress_rules) :
      r.cidr_ipv4 == null ? true : !contains(["0.0.0.0/0"], r.cidr_ipv4)
      || !(r.from_port <= 22 && r.to_port >= 22)
    ])
    error_message = "SSH (port 22) ne doit jamais être ouvert à 0.0.0.0/0."
  }

  validation {
    condition = alltrue([
      for r in values(var.ingress_rules) :
      r.cidr_ipv4 == null ? true : !contains(["0.0.0.0/0"], r.cidr_ipv4)
      || !(r.from_port <= 3389 && r.to_port >= 3389)
    ])
    error_message = "RDP (port 3389) ne doit jamais être ouvert à 0.0.0.0/0."
  }
}

variable "egress_rules" {
  description = "Règles sortantes, indexées par un nom statique. Vide = aucun trafic sortant. Même format que ingress_rules."
  type = map(object({
    description                  = string
    from_port                    = number
    to_port                      = number
    protocol                     = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.egress_rules) :
      can(regex("^[a-zA-Z0-9. _:/()#,@+=&;{}!$*\\[\\]-]+$", r.description))
    ])
    error_message = "Chaque description de règle ne doit contenir que des caractères acceptés par AWS (pas d'accents ni d'apostrophes)."
  }
}
