module "ecr" {
  for_each = local.create_ecr ? local.repositories : {}

  source  = "terraform-aws-modules/ecr/aws"
  version = "3.2.0"

  repository_image_tag_mutability = "MUTABLE"
  repository_name                 = "${var.app_name}-${each.value}-${local.svc_id}"
  repository_lifecycle_policy     = local.repository_lifecycle_policy

  tags = var.tags
}
