# Écoute en HTTP (80), pas HTTPS : un vrai certificat TLS demanderait un nom de domaine
# et une validation ACM, hors périmètre de ce portfolio. Le Security Group alb reste
# celui prévu en Phase 4 (443 configurable), cette démonstration ouvre le port 80 en plus,
# explicitement, uniquement pour ce test (voir dev/variables.tf : alb_allowed_http_cidrs).
locals {
  # aws_lb et aws_lb_target_group limitent leur "name" à 32 caractères (contrainte AWS,
  # détectée par `terraform plan`, pas par `validate`) : name_prefix seul (33 caractères
  # pour ce projet) le dépasse déjà. Troncature explicite plutôt qu'un nom générique.
  lb_name = substr("${var.name_prefix}-alb", 0, 32)
  tg_name = substr("${var.name_prefix}-tg", 0, 32)
}

resource "aws_lb" "this" {
  name               = local.lb_name
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.security_group_id]

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name        = local.tg_name
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 10
    timeout             = 5
  }

  tags = {
    Name = "${var.name_prefix}-app-tg"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = var.target_instance_id
  port             = var.target_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
