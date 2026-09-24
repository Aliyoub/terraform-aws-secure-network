data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Rôle IAM dédié à cette instance pour Systems Manager Session Manager : aucune clé SSH,
# aucun port entrant nécessaire (ADR-011). Distinct du rôle OIDC de la CI (Phase 7).
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.name_prefix}-ec2-ssm"
  description        = "Assume par EC2 - acces Systems Manager Session Manager uniquement"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = {
    Name = "${var.name_prefix}-ec2-ssm"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name_prefix}-ec2-ssm"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  # Aucune paire de clés : administration exclusivement via Session Manager (ADR-011).
  key_name = null

  # IMDSv2 obligatoire : bonne pratique de sécurité, empêche l'exploitation du service
  # de métadonnées via une éventuelle vulnérabilité SSRF applicative.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # 30 Go minimum : l'instantané de l'AMI Amazon Linux 2023 la plus récente l'exige
  # (contrainte constatée à l'apply - "Volume of size 8GB is smaller than snapshot" -
  # ni validate ni plan ne la détectent, seul un appel RunInstances réel le révèle).
  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  user_data = var.user_data

  tags = {
    Name = "${var.name_prefix}-demo"
  }
}
