# ─── Application ──────────────────────────────────────────────────────────────

variable "app_name" {
  type        = string
  description = "Application/repository name. Dùng làm prefix cho tất cả resources."
}

variable "environment" {
  type        = string
  description = "Deployment environment label (staging | production). Dùng trong resource naming."

  validation {
    condition     = contains(["staging", "production", "stg", "prod", "dev", "test"], var.environment)
    error_message = "environment phải là một trong: staging, production, stg, prod, dev, test."
  }
}

variable "env" {
  type        = string
  description = "Short environment alias (stg | prod | dev). Dùng làm prefix cho ECR repository names."

  validation {
    condition     = contains(["stg", "prod", "dev", "test"], var.env)
    error_message = "env phải là một trong: stg, prod, dev, test."
  }
}

# ─── Container Images ─────────────────────────────────────────────────────────

variable "app_repository_url" {
  type        = string
  default     = null
  description = <<-EOT
    URL ECR repository cho app image. CI/CD inject sau bước tạo ECR (ecr.tf).
    Ví dụ: 890970452363.dkr.ecr.ap-southeast-1.amazonaws.com/stg-reward-hub-app
    Null khi chỉ chạy bước tạo ECR.
  EOT
}

variable "nginx_repository_url" {
  type        = string
  default     = null
  description = <<-EOT
    URL ECR repository cho nginx image. CI/CD inject sau bước tạo ECR (ecr.tf).
    Ví dụ: 890970452363.dkr.ecr.ap-southeast-1.amazonaws.com/stg-reward-hub-nginx
    Null khi chỉ chạy bước tạo ECR.
  EOT
}

variable "image_tag" {
  type        = string
  default     = null
  description = "Docker image tag cho app container. CI/CD inject per deploy. Ví dụ: abc1234 (commit SHA)."
}

# ─── Network ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region để deploy resources."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID nơi các ECS resources sẽ được deploy."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Danh sách public subnet IDs (dành cho services có is_public=true trong manifest)."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Danh sách private subnet IDs (dành cho services có is_public=false trong manifest — default)."
}

# ─── ECS ──────────────────────────────────────────────────────────────────────

variable "ecs_cluster_id" {
  type        = string
  description = "ID của ECS Cluster đã tồn tại để deploy services vào."
}

variable "ecs_cluster_name" {
  type        = string
  description = "Tên ECS Cluster (dùng cho CloudWatch log naming)."
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

variable "alb_listener_arn" {
  type        = string
  default     = null
  description = <<-EOT
    ARN của ALB HTTPS Listener để gắn routing rules vào.
    CI/CD inject tùy theo environment (stg dùng ALB staging, prod dùng ALB production).
    Null khi không deploy ALB rules (bước ECR only hoặc không có service public).
  EOT
}

variable "alb_security_group_id" {
  type        = string
  default     = null
  description = "Security Group ID của ALB. Dùng để cho phép traffic từ ALB vào ECS tasks."
}

variable "alb_rule_priority_base" {
  type        = number
  default     = 100
  description = <<-EOT
    Priority base cho ALB listener rules khi manifest không khai báo priority.
    Rules sẽ được gán priority bắt đầu từ giá trị này.
    Priority trong manifest.json sẽ override giá trị này.
  EOT
}

# ─── Container / Service Config ───────────────────────────────────────────────

variable "default_container_port" {
  type        = number
  default     = 8080
  description = "Default container port nếu service không khai báo port trong manifest."
}

variable "default_cpu" {
  type        = number
  default     = 256
  description = "Default CPU units cho ECS task (1024 = 1 vCPU)."
}

variable "default_memory" {
  type        = number
  default     = 512
  description = "Default memory (MB) cho ECS task."
}

variable "default_desired_count" {
  type        = number
  default     = 1
  description = "Default số lượng ECS task instances."
}

variable "service_cpu" {
  type        = map(number)
  default     = {}
  description = "Override CPU per service. Map của service_name => cpu_units. Ví dụ: { api = 512 }"
}

variable "service_memory" {
  type        = map(number)
  default     = {}
  description = "Override memory per service. Map của service_name => memory_mb. Ví dụ: { api = 1024 }"
}

variable "service_desired_count" {
  type        = map(number)
  default     = {}
  description = "Override desired count per service. Map của service_name => count. Ví dụ: { api = 2 }"
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags gắn vào tất cả resources."
}