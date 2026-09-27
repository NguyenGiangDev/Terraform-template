locals {
  # ─── Parse manifest.json ─────────────────────────────────────────────────────
  # manifest.json hỗ trợ JS-style comments (//) để developer có thể thêm ghi chú.
  # Bước này strip tất cả comments trước khi parse JSON.
  # LƯU Ý: Tránh dùng "//" bên trong string values (ví dụ: URL https://... sẽ bị cắt).
  _manifest_raw     = file("${path.root}/manifest.json")
  _manifest_cleaned = replace(local._manifest_raw, "/\\s*\\/\\/[^\\n]*/", "")
  manifest          = jsondecode(local._manifest_cleaned)

  # ─── Top-level sections ──────────────────────────────────────────────────────
  services     = try(local.manifest.services, {})
  iam_policies = try(local.manifest.iam_policies, {})

  # Policy ARNs cần attach vào ECS Task Role
  iam_policy_arns = values(local.iam_policies)

  # ─── ECR ─────────────────────────────────────────────────────────────────────
  # create_ecr: đọc từ manifest (default true)
  # Set false trong manifest nếu ECR repos đã tồn tại và không cần recreate.
  create_ecr = try(local.manifest.create_ecr, true)

  # ECR repo names: {env}-{app_name}-{key}
  ecr_repos = {
    app   = "${var.env}-${var.app_name}-app"
    nginx = "${var.env}-${var.app_name}-nginx"
  }

  # Lifecycle policy: giữ tối đa 30 images gần nhất, expire các image cũ hơn
  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images, expire older ones"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })

  # ─── Image URIs ───────────────────────────────────────────────────────────────
  # nginx luôn dùng :latest (CI/CD rebuild mỗi deploy)
  # app dùng tag cụ thể từ CI/CD — đảm bảo traceability & rollback
  nginx_image = var.nginx_repository_url != null ? "${var.nginx_repository_url}:latest" : null
  app_image   = var.app_repository_url != null ? "${var.app_repository_url}:${var.image_tag}" : null

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
      # Launch type: EC2 (default) hoặc FARGATE
      # EC2    → dùng CPU/RAM của EC2 instance, không cần khai báo ở task level
      # FARGATE → AWS quản lý infra, bắt buộc phải khai báo cpu/memory ở task level
      launch_type = upper(try(svc.launch_type, "EC2"))

      # Port: manifest > default variable
      port = try(svc.port, var.default_container_port)

      # CPU/Memory: variable override > manifest value > default variable
      # Dùng cho container-level definitions (áp dụng cho cả EC2 lẫn FARGATE)
      cpu           = try(var.service_cpu[name], try(svc.cpu, var.default_cpu))
      memory        = try(var.service_memory[name], try(svc.memory, var.default_memory))
      desired_count = try(var.service_desired_count[name], try(svc.desired_count, var.default_desired_count))

      # Task-level CPU/Memory (field cpu/memory của aws_ecs_task_definition):
      #   FARGATE → bắt buộc phải có, lấy từ variable override > manifest > default
      #   EC2     → null (AWS tự tính từ tổng container cpu/memory trên instance)
      task_cpu    = upper(try(svc.launch_type, "EC2")) == "FARGATE" ? try(var.service_cpu[name], try(svc.cpu, var.default_cpu)) : null
      task_memory = upper(try(svc.launch_type, "EC2")) == "FARGATE" ? try(var.service_memory[name], try(svc.memory, var.default_memory)) : null

      # Subnet selection:
      #   is_public = false (default) → private subnets (tasks ẩn sau ALB)
      #   is_public = true            → public subnets (tasks có public IP)
      subnet_ids = try(svc.is_public, false) ? var.public_subnet_ids : var.private_subnet_ids

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
  # Naming: {app_name}-{service_name}-{port}-tg
  # AWS limit: tên TG tối đa 32 ký tự → tự động truncate nếu quá dài
  tg_names = {
    for name, svc in local.services_with_tg :
    name => substr(
      "${var.app_name}-${name}-${try(svc.port, var.default_container_port)}-tg",
      0, 32
    )
  }

  # ─── ALB Listener Rules (flatten từ mapping arrays) ──────────────────────────
  # Mỗi service có thể có nhiều mapping rules (mảng).
  # Flatten thành 1 map phẳng với key duy nhất: "{svc_name}-rule-{idx}"

  # Sort service keys để đảm bảo thứ tự ổn định khi tính priority tự động
  _mapping_service_keys_sorted = sort(keys(local.services_with_mapping))

  alb_rules = merge([
    for svc_name, svc in local.services_with_mapping : {
      for idx, rule in svc.mapping :
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
