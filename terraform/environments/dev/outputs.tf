output "aws_region" {
  description = "Région ciblée par cet environnement."
  value       = var.aws_region
}

output "tags" {
  description = "Tags appliqués par défaut à toutes les ressources."
  value       = local.tags
}
