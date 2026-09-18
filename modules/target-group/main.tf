resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = var.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  # "ip" target type bắt buộc với awsvpc network mode (ECS EC2 + awsvpc)
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy
    unhealthy_threshold = var.health_check_unhealthy
    matcher             = "200-299"
  }

  # Tránh lỗi khi Terraform cần recreate TG đang được dùng bởi ALB rule
  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}
