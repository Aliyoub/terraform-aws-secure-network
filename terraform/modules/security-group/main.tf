resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-${var.name}-sg"
  description = var.description
  vpc_id      = var.vpc_id

  # Aucune règle inline : les règles sont des ressources séparées ci-dessous.
  # Terraform supprime la règle « tout autoriser en sortie » créée par défaut par AWS.

  tags = {
    Name = "${var.name_prefix}-${var.name}-sg"
    Role = var.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.referenced_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.referenced_security_group_id
}
