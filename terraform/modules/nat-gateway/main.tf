# Elastic IP + NAT Gateway. Un seul NAT (dans une AZ) pour les deux AZ du projet :
# suffisant pour une démonstration, moins résilient qu'un NAT par AZ en production
# (ADR de la Phase 11 : compromis assumé pour limiter le coût et la complexité).
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_id

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}
