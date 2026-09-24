output "instance_id" {
  description = "Identifiant de l'instance."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Adresse IP privée de l'instance."
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "AMI utilisée (Amazon Linux 2023 la plus récente au moment du apply)."
  value       = data.aws_ami.amazon_linux.id
}
