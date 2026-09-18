variable "listener_arn" {
  type        = string
  description = "ARN của ALB Listener để gắn rule vào."
}

variable "priority" {
  type        = number
  description = "Priority của listener rule (1-50000, phải unique trên cùng 1 listener)."
}

variable "domains" {
  type        = list(string)
  description = "Danh sách domain names để route traffic (host-header matching)."
}

variable "target_group_arn" {
  type        = string
  description = "ARN của Target Group để forward traffic đến."
}
