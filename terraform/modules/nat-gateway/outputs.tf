output "nat_gateway_id" {
  description = "Identifiant du NAT Gateway."
  value       = aws_nat_gateway.this.id
}

output "eip_public_ip" {
  description = "Adresse IP publique de l'Elastic IP associée au NAT Gateway."
  value       = aws_eip.nat.public_ip
}
