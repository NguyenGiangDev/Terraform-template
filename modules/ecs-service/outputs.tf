output "service_arn" {
  description = "ARN của ECS Service"
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN của ECS Task Definition (revision hiện tại)"
  value       = aws_ecs_task_definition.this.arn
}

output "security_group_id" {
  description = "ID của Security Group gắn với ECS tasks"
  value       = aws_security_group.ecs_task.id
}

output "cloudwatch_log_group" {
  description = "Tên CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.this.name
}
