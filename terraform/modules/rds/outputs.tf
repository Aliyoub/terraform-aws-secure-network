output "endpoint" {
  description = "Point de terminaison (hôte:port) de l'instance RDS."
  value       = aws_db_instance.this.endpoint
}

output "database_name" {
  description = "Nom de la base de données."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Nom d'utilisateur administrateur."
  value       = aws_db_instance.this.username
}

output "master_password" {
  description = "Mot de passe généré. Sensible : jamais affiché par défaut (terraform output -raw pour le lire explicitement)."
  value       = random_password.master.result
  sensitive   = true
}
