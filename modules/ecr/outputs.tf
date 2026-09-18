output "repository_urls" {
  description = "Map key => ECR repository URL. Dùng làm image URI prefix trong CI/CD."
  value = {
    for k, mod in module.ecr : k => mod.repository_url
  }
}

output "repository_arns" {
  description = "Map key => ECR repository ARN."
  value = {
    for k, mod in module.ecr : k => mod.repository_arn
  }
}
