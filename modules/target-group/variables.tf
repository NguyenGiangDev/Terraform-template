variable "name" {
  type        = string
  description = "Tên Target Group (max 32 ký tự). Format: {app_name}-{service_name}-{port}-tg"
}

variable "port" {
  type        = number
  description = "Port mà ECS tasks lắng nghe."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "health_check_path" {
  type        = string
  default     = "/up"
  description = "Endpoint health check. Default: /up"
}

variable "health_check_interval" {
  type        = number
  default     = 30
  description = "Giây giữa các health check. Default: 30"
}

variable "health_check_timeout" {
  type        = number
  default     = 5
  description = "Timeout (giây) cho mỗi health check. Default: 5"
}

variable "health_check_healthy" {
  type        = number
  default     = 2
  description = "Số lần thành công liên tiếp để target được coi là healthy. Default: 2"
}

variable "health_check_unhealthy" {
  type        = number
  default     = 3
  description = "Số lần thất bại liên tiếp để target bị coi là unhealthy. Default: 3"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags gắn vào Target Group."
}
