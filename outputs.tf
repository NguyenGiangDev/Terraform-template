output "ecs_service_arns" {
  description = "Map service_name => ECS Service ARN"
  value = {
    for name, mod in module.ecs_service :
    name => mod.service_arn
  }
}

output "ecs_task_definition_arns" {
  description = "Map service_name => ECS Task Definition ARN (latest revision)"
  value = {
    for name, mod in module.ecs_service :
    name => mod.task_definition_arn
  }
}

output "target_group_arns" {
  description = "Map service_name => ALB Target Group ARN"
  value = {
    for name, mod in module.target_group :
    name => mod.target_group_arn
  }
}

output "target_group_names" {
  description = "Map service_name => ALB Target Group Name"
  value = {
    for name, mod in module.target_group :
    name => mod.target_group_name
  }
}

output "alb_rule_arns" {
  description = "Map rule_key => ALB Listener Rule ARN"
  value = {
    for key, mod in module.alb_rule :
    key => mod.rule_arn
  }
}

output "ecs_task_security_group_ids" {
  description = "Map service_name => ECS Task Security Group ID"
  value = {
    for name, mod in module.ecs_service :
    name => mod.security_group_id
  }
}

output "cloudwatch_log_groups" {
  description = "Map service_name => CloudWatch Log Group name"
  value = {
    for name, mod in module.ecs_service :
    name => mod.cloudwatch_log_group
  }
}

output "task_execution_role_arn" {
  description = "ARN của ECS Task Execution IAM Role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN của ECS Task IAM Role (container permissions)"
  value       = aws_iam_role.task.arn
}

output "ecr_repository_urls" {
  description = "Map key => ECR repository URL (nginx/app). Dùng làm image URI prefix trong CI/CD."
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map key => ECR repository ARN."
  value       = module.ecr.repository_arns
}
