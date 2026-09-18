# Remote State Configuration
# ─────────────────────────────────────────────────────────────────────────────
# Uncomment và điền thông tin S3 bucket để dùng remote state.
# LƯU Ý: Các giá trị ở đây KHÔNG thể dùng Terraform variables.
#
# terraform {
#   backend "s3" {
#     bucket         = "gotit-terraform-state"
#     key            = "reward-hub/stg/terraform.tfstate"  # format: {app}/{env}/terraform.tfstate
#     region         = "ap-southeast-1"
#     dynamodb_table = "terraform-state-lock"
#     encrypt        = true
#   }
# }
#
# ─── Tạo S3 bucket và DynamoDB table (chạy 1 lần) ────────────────────────────
# aws s3api create-bucket \
#   --bucket gotit-terraform-state \
#   --region ap-southeast-1 \
#   --create-bucket-configuration LocationConstraint=ap-southeast-1
#
# aws s3api put-bucket-versioning \
#   --bucket gotit-terraform-state \
#   --versioning-configuration Status=Enabled
#
# aws dynamodb create-table \
#   --table-name terraform-state-lock \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST \
#   --region ap-southeast-1
