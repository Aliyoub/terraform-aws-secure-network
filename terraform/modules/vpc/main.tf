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
