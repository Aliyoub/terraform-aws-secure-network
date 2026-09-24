# Security Group dédié aux endpoints : n'autorise le HTTPS (443) que depuis le CIDR
# du VPC. Les endpoints eux-mêmes n'ont pas de trafic entrant public possible (ce sont
# des ressources privées par construction), cette règle protège leur interface réseau.
resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-vpc-endpoints-sg"
  description = "HTTPS entrant depuis le VPC uniquement - endpoints d interface"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-vpc-endpoints-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https_from_vpc" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS depuis le CIDR du VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.service_names)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-vpce-${each.value}"
  }
}
