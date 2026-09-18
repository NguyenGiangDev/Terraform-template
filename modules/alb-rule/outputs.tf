output "rule_arn" {
  description = "ARN của ALB Listener Rule"
  value       = aws_lb_listener_rule.this.arn
}
