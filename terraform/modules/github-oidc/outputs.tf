output "role_arn" {
  description = "ARN du rôle IAM à endosser depuis GitHub Actions (aws-actions/configure-aws-credentials)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nom du rôle IAM."
  value       = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  description = "ARN du fournisseur OIDC GitHub Actions utilisé par ce rôle."
  value       = local.oidc_provider_arn
}
