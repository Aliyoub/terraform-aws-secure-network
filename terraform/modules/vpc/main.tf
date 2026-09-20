resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  # Instances gérées par défaut (pas de tenancy dédiée, plus coûteuse).
  instance_tenancy = "default"

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Table de routage principale du VPC, gérée explicitement et volontairement SANS route
# (seule la route locale du VPC subsiste). Tout subnet qui n'est associé à aucune table
# dédiée retombe sur celle-ci : il n'a donc jamais de sortie vers Internet par accident.
resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  # Liste vide explicite : Terraform supprime toute route ajoutée hors de son contrôle.
  route = []

  tags = {
    Name = "${var.name_prefix}-main-rt-no-routes"
  }
}

# Groupe de sécurité par défaut du VPC : adopté et vidé (aucune règle entrante ni sortante).
# Toute ressource lancée sans groupe explicite n'aurait ainsi aucun accès réseau.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  ingress = []
  egress  = []

  tags = {
    Name = "${var.name_prefix}-default-sg-no-rules"
  }
}
