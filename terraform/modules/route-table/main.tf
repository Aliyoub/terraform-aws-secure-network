resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-${var.tier}-rt"
    Tier = var.tier
  }
}

# Routes explicites uniquement. Une table sans entrée dans `routes` n'a que la route
# locale du VPC : ses subnets ne peuvent atteindre aucune destination hors du VPC.
resource "aws_route" "this" {
  for_each = var.routes

  route_table_id         = aws_route_table.this.id
  destination_cidr_block = each.value.destination_cidr_block
  gateway_id             = each.value.gateway_id
  nat_gateway_id         = each.value.nat_gateway_id
}

resource "aws_route_table_association" "this" {
  for_each = var.subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.this.id
}
