variable "name_prefix" {
  description = "Préfixe utilisé pour le nommage des ressources (ex. : terraform-aws-secure-network)."
  type        = string
}

variable "create_oidc_provider" {
  description = "Crée le fournisseur d'identité OIDC de GitHub Actions. Un seul par compte AWS : passer false et renseigner existing_oidc_provider_arn si un autre module ou une autre pile l'a déjà créé."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN d'un fournisseur OIDC GitHub Actions déjà existant. Utilisé uniquement si create_oidc_provider = false."
  type        = string
  default     = null
}

variable "thumbprint" {
  description = <<-EOT
    Empreinte SHA-1 exigée par l'API IAM pour le fournisseur OIDC. AWS l'utilise pour
    valider la chaîne de certificats de token.actions.githubusercontent.com au moment
    de la création du fournisseur (des IdP bien connus comme GitHub sont ensuite gérés
    par AWS indépendamment de cette valeur, mais le champ reste obligatoire).

    Valeur par défaut obtenue le 22/09/2026 avec :
      openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts
    en prenant l'empreinte SHA-1 du DERNIER certificat de la chaîne renvoyée par le
    serveur (l'autorité la plus haute qu'il présente), comme documenté par GitHub et AWS.
    À recalculer si la chaîne de certificats de GitHub change (cela s'est déjà produit).
  EOT
  type        = string
  default     = "ab9d0263244dd0326eb67015705a667e79cfe998"

  validation {
    condition     = can(regex("^[a-f0-9]{40}$", var.thumbprint))
    error_message = "thumbprint doit être une empreinte SHA-1 en hexadécimal minuscule (40 caractères)."
  }
}

variable "github_organization" {
  description = "Organisation ou compte GitHub propriétaire du dépôt (ex. : Aliyoub)."
  type        = string
}

variable "github_repository" {
  description = "Nom du dépôt GitHub (sans l'organisation), ex. : terraform-aws-secure-network."
  type        = string
}

variable "allowed_branches" {
  description = "Branches depuis lesquelles un push peut endosser le rôle (ex. : [\"main\"]). Vide si seules les pull requests doivent être autorisées."
  type        = list(string)
  default     = ["main"]
}

variable "allow_pull_requests" {
  description = "Autorise l'endossement du rôle depuis un workflow déclenché par une pull request sur ce dépôt (nécessaire pour un terraform plan en review, avant fusion)."
  type        = bool
  default     = true
}

variable "role_purpose" {
  description = "Rôle fonctionnel utilisé dans le nom de la ressource IAM (ex. : plan, apply)."
  type        = string
  default     = "plan"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.role_purpose))
    error_message = "role_purpose doit être en minuscules, alphanumérique et tirets uniquement."
  }
}

variable "role_description" {
  description = "Description du role IAM. AWS n'accepte ni accents ni apostrophes."
  type        = string
  default     = "Assume par GitHub Actions via OIDC - lecture seule, aucun apply automatique"

  validation {
    condition     = can(regex("^[a-zA-Z0-9. _:/()#,@+=&;{}!$*\\[\\]-]+$", var.role_description))
    error_message = "role_description ne doit contenir que des caractères acceptés par AWS (pas d'accents ni d'apostrophes)."
  }
}

variable "max_session_duration" {
  description = "Durée maximale (en secondes) d'une session assumée via ce rôle."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "max_session_duration doit être compris entre 900 (15 min) et 43200 (12 h)."
  }
}

variable "read_only_actions" {
  description = "Actions IAM en lecture seule accordées au rôle (ex. : ec2:Describe*). Aucune action de création, modification ou suppression ne doit y figurer : ce module ne le vérifie pas, la revue de code le doit."
  type        = list(string)
  default     = []
}
