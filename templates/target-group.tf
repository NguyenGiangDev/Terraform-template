# ─── ALB Target Groups ────────────────────────────────────────────────────────
# Tạo Target Group cho mỗi service có khai báo target_group trong manifest.json.
# Naming: {app_name}-{service_name}-{port}-tg (tự truncate về 32 ký tự)
# target_type = "ip" bắt buộc với awsvpc network mode (EC2 + awsvpc)

resource "aws_lb_target_group" "this" {
  for_each = local.services_with_tg

  name        = local.tg_names[each.key]
  port        = local.service_configs[each.key].port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = local.service_configs[each.key].health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = local.service_configs[each.key].health_check_interval
    timeout             = local.service_configs[each.key].health_check_timeout
    healthy_threshold   = local.service_configs[each.key].health_check_healthy
    unhealthy_threshold = local.service_configs[each.key].health_check_unhealthy
    matcher             = "200-299"
  }

  # Tránh lỗi khi TG đang được dùng bởi ALB rule cần recreate
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name    = local.tg_names[each.key]
    Service = each.key
  })
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "target_group_arns" {
  description = "Map service_name => ALB Target Group ARN"
  value = {
    for name, tg in aws_lb_target_group.this : name => tg.arn
  }
}

output "target_group_names" {
  description = "Map service_name => ALB Target Group Name"
  value = {
    for name, tg in aws_lb_target_group.this : name => tg.name
  }
}
