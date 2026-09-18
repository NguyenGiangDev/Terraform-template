# ALB Listener Rule - Host-header based routing
# Mỗi rule forward traffic từ 1 tập domain đến 1 target group.
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.priority

  action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  # Route dựa trên Host header (domain name)
  condition {
    host_header {
      values = var.domains
    }
  }
}
