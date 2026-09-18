output "target_group_arn" {
  description = "ARN của ALB Target Group"
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "Tên của ALB Target Group"
  value       = aws_lb_target_group.this.name
}
