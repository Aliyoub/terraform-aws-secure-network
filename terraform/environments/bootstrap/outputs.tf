output "aws_region" {
  description = "Région ciblée par cet environnement."
  value       = var.aws_region
}

output "github_actions_plan_role_arn" {
  description = "ARN du rôle à renseigner dans le workflow terraform-plan (role-to-assume)."
  value       = module.github_actions_plan_role.role_arn
}

output "github_oidc_provider_arn" {
  description = "ARN du fournisseur OIDC GitHub Actions créé dans ce compte."
  value       = module.github_actions_plan_role.oidc_provider_arn
}
