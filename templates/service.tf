# ─── CloudWatch Log Groups ────────────────────────────────────────────────────
# Tạo log group riêng cho mỗi service khai báo trong manifest.json → services.

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.service_configs

  name              = "/ecs/${var.app_name}/${var.environment}/${each.key}"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name    = "/ecs/${var.app_name}/${var.environment}/${each.key}"
    Service = each.key
  })
}

# ─── Security Groups (ECS Task) ───────────────────────────────────────────────
# Mỗi task có SG riêng với awsvpc network mode.
# Chỉ cho phép inbound từ ALB SG vào nginx port 80.

resource "aws_security_group" "ecs_task" {
  for_each = local.service_configs

  name        = "${var.environment}-${var.app_name}-${each.key}-sg"
  description = "SG for ECS task ${var.environment}-${var.app_name}-${each.key}"
  vpc_id      = var.vpc_id

  # Chỉ mở khi service có target_group (expose qua ALB)
  dynamic "ingress" {
    for_each = each.value.has_tg && var.alb_security_group_id != null ? [1] : []
    content {
      description     = "Allow inbound from ALB to nginx"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name    = "${var.environment}-${var.app_name}-${each.key}-sg"
    Service = each.key
  })
}

# ─── ECS Task Definitions ─────────────────────────────────────────────────────
# 2-container pattern: nginx (reverse proxy) + app container.
# nginx nhận traffic từ ALB (port 80), proxy vào app (port từ manifest).

resource "aws_ecs_task_definition" "this" {
  for_each = local.service_configs

  family                   = "${var.environment}-${var.app_name}-${each.key}"
  requires_compatibilities = [each.value.launch_type]
  network_mode             = "awsvpc"

  # EC2     → task_cpu/task_memory = null (không khai báo, EC2 instance tự cấp phát)
  # FARGATE → bắt buộc phải có, AWS dùng để chọn task size
  cpu    = each.value.task_cpu
  memory = each.value.task_memory

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    # ── nginx sidecar (reverse proxy) ────────────────────────────────────────
    # Entry point từ ALB. Nhận port 80, proxy tới app:{port}.
    {
      name      = "nginx"
      image     = local.nginx_image
      essential = true

      portMappings = [{
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }]

      # Đợi app container start trước
      dependsOn = [{
        containerName = each.key
        condition     = "START"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },

    # ── app container (api / worker / web / ...) ──────────────────────────────
    # Không expose trực tiếp ra ngoài, nginx proxy vào qua localhost.
    {
      name      = each.key
      image     = local.app_image
      cpu       = each.value.cpu
      memory    = each.value.memory
      essential = true

      portMappings = [{
        containerPort = each.value.port
        hostPort      = each.value.port
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = merge(var.tags, {
    Name    = "${var.environment}-${var.app_name}-${each.key}"
    Service = each.key
  })
}

# ─── ECS Services ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "this" {
  for_each = local.service_configs

  name            = "${var.environment}-${var.app_name}-${each.key}"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = each.value.launch_type

  network_configuration {
    subnets         = each.value.subnet_ids
    security_groups = [aws_security_group.ecs_task[each.key].id]
  }

  # Gắn TG nếu service có khai báo target_group trong manifest
  dynamic "load_balancer" {
    for_each = each.value.has_tg ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[each.key].arn
      container_name   = "nginx"
      container_port   = 80
    }
  }

  # Rolling deployment: luôn có ít nhất 50% tasks healthy
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # CI/CD update task_definition trực tiếp; Auto Scaling quản lý desired_count
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
    ]
  }

  tags = merge(var.tags, {
    Name    = "${var.environment}-${var.app_name}-${each.key}"
    Service = each.key
  })

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_managed,
    aws_iam_role_policy_attachment.task_additional,
  ]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "ecs_service_arns" {
  description = "Map service_name => ECS Service ARN"
  value = {
    for name, svc in aws_ecs_service.this : name => svc.id
  }
}

output "ecs_task_definition_arns" {
  description = "Map service_name => ECS Task Definition ARN (latest revision)"
  value = {
    for name, td in aws_ecs_task_definition.this : name => td.arn
  }
}

output "ecs_task_security_group_ids" {
  description = "Map service_name => ECS Task Security Group ID"
  value = {
    for name, sg in aws_security_group.ecs_task : name => sg.id
  }
}

output "cloudwatch_log_groups" {
  description = "Map service_name => CloudWatch Log Group name"
  value = {
    for name, lg in aws_cloudwatch_log_group.this : name => lg.name
  }
}
