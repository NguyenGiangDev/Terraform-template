# ─── ALB Listener Rules ───────────────────────────────────────────────────────
# Tạo host-header routing rules trên ALB listener.
# Mỗi rule forward traffic từ domain(s) → target group tương ứng.
# ALB Listener được inject từ CI/CD theo environment (var.alb_listener_arn).

resource "aws_lb_listener_rule" "this" {
  for_each = local.alb_rules

  listener_arn = var.alb_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.service_name].arn
  }

  # Route dựa trên Host header (domain name)
  condition {
    host_header {
      values = each.value.domains
    }
  }

  depends_on = [aws_lb_target_group.this]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "alb_rule_arns" {
  description = "Map rule_key => ALB Listener Rule ARN"
  value = {
    for key, rule in aws_lb_listener_rule.this : key => rule.arn
  }
}
