# ─── Application ──────────────────────────────────────────────────────────────

variable "app_name" {
  type        = string
  description = "Application/repository name. Dùng làm prefix cho tất cả resources."
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev | stg | prod)."
}

variable "env" {
  type        = string
  description = "Short environment alias (dev|stg|prod). Dùng làm prefix cho ECR repository name và đọc file {env}-manifest.json."
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

variable "NGINX_REPOSITORY_URL" {
  type        = string
  default     = null
  description = "URL của ECR repository dành cho nginx image. Nếu null → bỏ qua, không tạo nginx ECR repo."
}

variable "APP_REPOSITORY_URL" {
  type        = string
  default     = null
  description = "URL của ECR repository dành cho app image. Nếu null → bỏ qua, không tạo app ECR repo."
}

variable "image_tag" {
  type        = string
  description = "Docker image tag cho app container. CI/CD cung cấp per deploy. Ví dụ: abc1234, v1.2.3."
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
  description = "Danh sách private subnet IDs (dành cho services có is_public=false trong manifest - default)."
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
  description = <<-EOT
    ARN của ALB HTTPS Listener để gắn routing rules vào.
    Được CI/CD inject tùy theo environment (stg dùng ALB staging, prod dùng ALB production).
  EOT
}

variable "alb_security_group_id" {
  type        = string
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
  description = "Override CPU per service. Map của service_name => cpu_units."
}

variable "service_memory" {
  type        = map(number)
  default     = {}
  description = "Override memory per service. Map của service_name => memory_mb."
}

variable "service_desired_count" {
  type        = map(number)
  default     = {}
  description = "Override desired count per service. Map của service_name => count."
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags gắn vào tất cả resources."
}