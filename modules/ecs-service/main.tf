locals {
  # Tên chuẩn dùng cho tất cả resources trong module này
  name = "${var.environment}-${var.app_name}-${var.service_name}"
}

# ─── CloudWatch Log Group ─────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.app_name}/${var.environment}/${var.service_name}"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name    = "/ecs/${var.app_name}/${var.environment}/${var.service_name}"
    Service = var.service_name
  })
}

# ─── Security Group cho ECS Task ─────────────────────────────────────────────
# Dùng với awsvpc network mode: mỗi task có ENI riêng với SG riêng.
resource "aws_security_group" "ecs_task" {
  name        = "${local.name}-sg"
  description = "SG for ECS task ${local.name}"
  vpc_id      = var.vpc_id

  # Cho phép traffic từ ALB vào nginx port 80 (chỉ khi service có target_group)
  dynamic "ingress" {
    for_each = var.alb_security_group_id != null ? [1] : []
    content {
      description     = "Allow inbound from ALB to nginx"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
    }
  }

  # Cho phép tất cả outbound (để container gọi AWS APIs, download packages, etc.)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name    = "${local.name}-sg"
    Service = var.service_name
  })
}

# ─── ECS Task Definition ──────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "this" {
  family                   = local.name
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    # ─── nginx (reverse proxy) ─────────────────────────────────────────────────────
    # Entry point cho ALB. Nhận traffic port 80, proxy tới app:${var.port}.
    {
      name      = "nginx"
      image     = var.nginx_image
      essential = true

      portMappings = [{
        containerPort = 80
        hostPort      = 80
        protocol      = "tcp"
      }]

      # Khởi động nginx sau khi service container đã start
      dependsOn = [{
        containerName = var.service_name
        condition     = "START"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },

    # ─── service container (backend / api / worker / web / schedule / ...) ─────────────
    # Tên container = service_name từ manifest.json.
    # Không expose trực tiếp ra ngoài, nginx proxy tới qua localhost.
    {
      name      = var.service_name
      image     = var.image
      cpu       = var.cpu
      memory    = var.memory
      essential = true

      portMappings = [{
        containerPort = var.port
        hostPort      = var.port
        protocol      = "tcp"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = merge(var.tags, {
    Name    = local.name
    Service = var.service_name
  })
}

# ─── ECS Service ──────────────────────────────────────────────────────────────
resource "aws_ecs_service" "this" {
  name            = local.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "EC2"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [aws_security_group.ecs_task.id]
  }

  # ALB forward tới nginx container port 80 (nginx sẽ proxy tiếp vào app)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = "nginx"
      container_port   = 80
    }
  }

  # Rolling deployment: đảm bảo luôn có ít nhất 50% tasks healthy
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Không track changes trên task_definition và desired_count
  # → CI/CD sẽ update task_definition trực tiếp, desired_count quản lý bởi Auto Scaling
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
    ]
  }

  tags = merge(var.tags, {
    Name    = local.name
    Service = var.service_name
  })
}
