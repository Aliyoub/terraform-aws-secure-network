output "vpc_id" {
  description = "Identifiant du VPC."
  value       = aws_vpc.this.id
}

output "cidr_block" {
  description = "Bloc CIDR du VPC."
  value       = aws_vpc.this.cidr_block
}
