# Un même module sert aux subnets publics et privés : c'est la table de routage
# associée (Phase 3) qui rend un subnet public ou privé, pas la ressource elle-même.
resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = {
    Name = "${var.name_prefix}-${var.tier}-${each.key}"
    Tier = var.tier
  }
}
