resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}

# Mot de passe généré par Terraform, jamais écrit en dur dans le code. Simplification
# assumée pour une démonstration courte : en production, préférer AWS Secrets Manager
# avec rotation automatique (non utilisé ici pour éviter un coût Secrets Manager sur
# une ressource destinée à vivre quelques minutes - voir docs/COSTS.md).
resource "random_password" "master" {
  length  = 20
  special = false # évite les caractères à échapper dans une chaîne de connexion
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = 20 # minimum RDS ; voir docs/COSTS.md pour le coût au Go-mois
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = false

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master.result

  # Pas de sauvegarde automatique, pas de snapshot final : évite tout coût de stockage
  # résiduel après un `terraform destroy` (piège identifié dans docs/COSTS.md).
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = {
    Name = "${var.name_prefix}-db"
  }
}
