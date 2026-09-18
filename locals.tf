locals {
  # source name
  svc_id = var.app_name
  # ─── Parse manifest.json ─────────────────────────────────────────────────────
  # manifest.json hỗ trợ JS-style comments (//) để developer có thể thêm ghi chú.
  # Bước này strip tất cả comments trước khi parse JSON.
  # LƯU Ý: Tránh dùng "//" bên trong string values của JSON (ví dụ: trong URL).
  _manifest_raw     = file("${path.root}/manifest.json")
  _manifest_cleaned = replace(local._manifest_raw, "/\\s*\\/\\/[^\\n]*/", "")
  manifest          = jsondecode(local._manifest_cleaned)

  # ─── Top-level sections ──────────────────────────────────────────────────────
  services     = try(local.manifest.services, {})
  iam_policies = try(local.manifest.iam_policies, {})

  # Danh sách policy ARNs cần attach vào ECS Task Role
  iam_policy_arns = values(local.iam_policies)

  # ─── ECR repositories ──────────────────────────────────────────────────────
  create_ecr           = try(jsondecode(file("${path.module}/${var.env}-manifest.json")).create_ecr, true)
  nginx_ecr_repository = (var.NGINX_REPOSITORY_URL != null && var.NGINX_REPOSITORY_URL != "") ? var.NGINX_REPOSITORY_URL : null
  app_ecr_repository   = (var.APP_REPOSITORY_URL   != null && var.APP_REPOSITORY_URL   != "") ? var.APP_REPOSITORY_URL   : null
  repositories = merge(
    local.nginx_ecr_repository != null ? { nginx = "${var.env}-nginx" } : {},
    local.app_ecr_repository   != null ? { app   = "${var.env}-app"   } : {}
  )

  # Image URIs — tính tự động từ ECR repo URL
  # nginx luôn dùng :latest (image được rebuild mỗi deploy bởi CI/CD)
  nginx_image = "${var.NGINX_REPOSITORY_URL}:latest"
  # app dùng tag cụ thể từ CI/CD — đảm bảo traceability & rollback
  app_image   = "${var.APP_REPOSITORY_URL}:${var.image_tag}"

  # Lifecycle policy: giữ tối đa 30 images gần nhất, expire các image cũ hơn
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images, expire older ones"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
  # ─── Service filters ─────────────────────────────────────────────────────────

  # Services có khai báo target_group → sẽ tạo ALB Target Group
  services_with_tg = {
    for name, svc in local.services :
    name => svc
    if try(svc.target_group, null) != null
  }

  # Services có khai báo mapping → sẽ tạo ALB Listener Rules
  services_with_mapping = {
    for name, svc in local.services :
    name => svc
    if try(svc.mapping, null) != null
  }

  # ─── Resolved service configuration ──────────────────────────────────────────
  # Merge giá trị từ manifest + variable overrides + defaults
  service_configs = {
    for name, svc in local.services :
    name => {
      # Port: manifest > default variable
      port = try(svc.port, var.default_container_port)

      # CPU/Memory/Count: variable override > manifest value > default variable
      cpu           = try(var.service_cpu[name], try(svc.cpu, var.default_cpu))
      memory        = try(var.service_memory[name], try(svc.memory, var.default_memory))
      desired_count = try(var.service_desired_count[name], try(svc.desired_count, var.default_desired_count))

      # Subnet selection:
      #   is_public = false (default) → private subnets (tasks ẩn sau ALB, không có public IP)
      #   is_public = true            → public subnets (tasks có public IP, dùng cho edge cases)
      subnet_ids = try(svc.is_public, false) ? var.public_subnet_ids : var.private_subnet_ids

      # App image URI — tính tự động từ APP_REPOSITORY_URL + image_tag
      image = local.app_image

      # Feature flags
      has_tg      = try(svc.target_group, null) != null
      has_mapping = try(svc.mapping, null) != null

      # Health check config (chỉ dùng nếu has_tg = true)
      health_check_path       = try(svc.target_group.health_check.path, "/up")
      health_check_interval   = try(svc.target_group.health_check.interval, 30)
      health_check_timeout    = try(svc.target_group.health_check.timeout, 5)
      health_check_healthy    = try(svc.target_group.health_check.healthy_threshold, 2)
      health_check_unhealthy  = try(svc.target_group.health_check.unhealthy_threshold, 3)
    }
  }

  # ─── Target Group names ───────────────────────────────────────────────────────
  # Naming convention: {app_name}-{service_name}-{port}-tg
  # AWS limit: tên TG tối đa 32 ký tự → tự động truncate nếu quá dài
  tg_names = {
    for name, svc in local.services_with_tg :
    name => substr(
      "${var.app_name}-${name}-${try(svc.port, var.default_container_port)}-tg",
      0,
      32
    )
  }

  # ─── ALB Listener Rules (flatten từ mapping arrays) ──────────────────────────
  # Mỗi service có thể có nhiều mapping rules (mảng).
  # Ta flatten tất cả thành 1 map phẳng với key duy nhất: "{svc_name}-rule-{idx}"

  # Sort service keys để đảm bảo thứ tự ổn định khi tính priority tự động
  _mapping_service_keys_sorted = sort(keys(local.services_with_mapping))

  alb_rules = merge([
    for svc_name, svc in local.services_with_mapping : {
      for idx, rule in svc.mapping :
      # Key duy nhất cho mỗi rule
      "${svc_name}-rule-${idx}" => {
        service_name = svc_name
        domains      = rule.domain

        # Priority:
        #   1. Lấy từ manifest nếu được khai báo (rule.priority)
        #   2. Tự tính: base + (vị_trí_service * 20) + index_rule
        priority = try(
          rule.priority,
          var.alb_rule_priority_base + (index(local._mapping_service_keys_sorted, svc_name) * 20) + idx
        )
      }
    }
  ]...)
}
