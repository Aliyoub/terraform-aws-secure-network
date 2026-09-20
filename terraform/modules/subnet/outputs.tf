output "subnet_ids" {
  description = "Identifiants des subnets, indexés par la même clé que l'entrée subnets."
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "availability_zones" {
  description = "Zones de disponibilité utilisées, indexées par la même clé que l'entrée subnets."
  value       = { for k, s in aws_subnet.this : k => s.availability_zone }
}
