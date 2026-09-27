# ─── ECR Repositories ─────────────────────────────────────────────────────────
# Tạo ECR repos cho app và nginx khi create_ecr = true (default) trong manifest.json.
# Naming: {env}-{app_name}-{key}  (key = "app" | "nginx")
#
# CI/CD flow:
#   Step 1 — copy ecr.tf vào working dir → terraform apply → ECR repos được tạo
#   Step 2 — CI/CD đọc output ecr_repository_urls → build & push Docker images
#   Step 3 — copy service.tf + target-group.tf + alb-rule.tf → terraform apply

resource "aws_ecr_repository" "this" {
  for_each = local.create_ecr ? local.ecr_repos : {}

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = merge(var.tags, {
    Name = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = local.create_ecr ? local.ecr_repos : {}
  repository = aws_ecr_repository.this[each.key].name

  policy = local.repository_lifecycle_policy
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "Map key => ECR repository URL. CI/CD dùng để build & push Docker images."
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map key => ECR repository ARN."
  value = {
    for k, repo in aws_ecr_repository.this : k => repo.arn
  }
}
