variable "app_name" {
  type        = string
  description = "Application name (prefix cho tất cả resources)."
}

variable "service_name" {
  type        = string
  description = "Tên service (key trong manifest.json → services)."
}

variable "environment" {
  type        = string
  description = "Deployment environment."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
}

variable "cluster_id" {
  type        = string
  description = "ECS Cluster ID."
}

variable "cluster_name" {
  type        = string
  description = "ECS Cluster name."
}

variable "image" {
  type        = string
  description = "Full Docker image URI cho app container."
}

variable "nginx_image" {
  type        = string
  description = "Full Docker image URI cho nginx sidecar (reverse proxy). Ví dụ: 123456.dkr.ecr.ap-southeast-1.amazonaws.com/app/nginx:tag."
}

variable "port" {
  type        = number
  description = "Container port expose ra ngoài."
}

variable "cpu" {
  type        = number
  description = "CPU units cho ECS task (1024 = 1 vCPU)."
}

variable "memory" {
  type        = number
  description = "Memory (MB) cho ECS task."
}

variable "desired_count" {
  type        = number
  description = "Số lượng task instances."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs để đặt ECS tasks (private hoặc public, xác định bởi is_public trong manifest)."
}

variable "execution_role_arn" {
  type        = string
  description = "ARN của ECS Task Execution IAM Role."
}

variable "task_role_arn" {
  type        = string
  description = "ARN của ECS Task IAM Role (container permissions)."
}

variable "target_group_arn" {
  type        = string
  default     = null
  description = "ARN của ALB Target Group. Null nếu service không expose qua ALB."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "alb_security_group_id" {
  type        = string
  default     = null
  description = "Security Group ID của ALB. Dùng để tạo inbound rule cho ECS task SG."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags gắn vào tất cả resources của module này."
}
