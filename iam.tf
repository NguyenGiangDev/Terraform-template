# ─── Task Execution Role ──────────────────────────────────────────────────────
# ECS Agent dùng role này để: pull image từ ECR, gửi logs lên CloudWatch,
# đọc secrets từ SSM Parameter Store / Secrets Manager.

resource "aws_iam_role" "task_execution" {
  name = "${var.app_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ECSTasksAssumeRole"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.app_name}-${var.environment}-ecs-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ─── Task Role ────────────────────────────────────────────────────────────────
# Container dùng role này khi gọi AWS APIs (S3, SQS, DynamoDB...).
# Các policy ARN được khai báo trong manifest.json → iam_policies section.

resource "aws_iam_role" "task" {
  name = "${var.app_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ECSTasksAssumeRole"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.app_name}-${var.environment}-ecs-task-role"
  })
}

# Attach các custom policies từ manifest.json → iam_policies
# Key của map (s3, sqs, ...) chỉ dùng cho Terraform resource naming, không quan trọng.
resource "aws_iam_role_policy_attachment" "task_additional" {
  for_each = local.iam_policies

  role       = aws_iam_role.task.name
  policy_arn = each.value
}
