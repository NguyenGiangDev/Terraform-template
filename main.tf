# ─── ECS Services ─────────────────────────────────────────────────────────────
# Tạo ECS Task Definition + ECS Service + Security Group + CloudWatch Log Group
# cho mỗi service được khai báo trong manifest.json → services

module "ecs_service" {
  for_each = local.service_configs
  source   = "./modules/ecs-service"

  app_name     = var.app_name
  service_name = each.key
  environment  = var.environment
  aws_region   = var.aws_region

  cluster_id   = var.ecs_cluster_id
  cluster_name = var.ecs_cluster_name

  image         = each.value.image
  nginx_image   = local.nginx_image
  port          = each.value.port
  cpu           = each.value.cpu
  memory        = each.value.memory
  desired_count = each.value.desired_count
  subnet_ids    = each.value.subnet_ids

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  # Attach target group nếu service có khai báo target_group trong manifest
  target_group_arn = each.value.has_tg ? module.target_group[each.key].target_group_arn : null

  vpc_id                = var.vpc_id
  alb_security_group_id = var.alb_security_group_id

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_iam_role_policy_attachment.task_additional,
  ]
}

# ─── ALB Target Groups ────────────────────────────────────────────────────────
# Tạo Target Group cho mỗi service có khai báo target_group trong manifest.
# Naming: {app_name}-{service_name}-{port}-tg (max 32 chars, tự truncate)

module "target_group" {
  for_each = local.services_with_tg
  source   = "./modules/target-group"

  name   = local.tg_names[each.key]
  port   = local.service_configs[each.key].port
  vpc_id = var.vpc_id

  health_check_path       = local.service_configs[each.key].health_check_path
  health_check_interval   = local.service_configs[each.key].health_check_interval
  health_check_timeout    = local.service_configs[each.key].health_check_timeout
  health_check_healthy    = local.service_configs[each.key].health_check_healthy
  health_check_unhealthy  = local.service_configs[each.key].health_check_unhealthy

  tags = merge(var.tags, {
    Service = each.key
  })
}

# ─── ALB Listener Rules ────────────────────────────────────────────────────────
# Tạo ALB host-header routing rules từ manifest.json → services[*].mapping[*].domain
# Mỗi rule forward traffic từ domain đến target group tương ứng.
# ALB listener được xác định qua biến alb_listener_arn (inject từ CI/CD theo environment).

module "alb_rule" {
  for_each = local.alb_rules
  source   = "./modules/alb-rule"

  listener_arn     = var.alb_listener_arn
  priority         = each.value.priority
  domains          = each.value.domains
  target_group_arn = module.target_group[each.value.service_name].target_group_arn

  depends_on = [module.target_group]
}
