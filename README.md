# Terraform Template — ECS on AWS

Template deploy ECS workload lên AWS, thiết kế để tích hợp vào GitHub Actions CI/CD pipeline.

## Tài nguyên có sẵn (pre-existing)
- VPC, Subnets (public + private)
- Application Load Balancer (ALB) + Listener
- ECS Cluster (EC2 launch type)

## Tài nguyên được tạo tự động
| File | Resources |
|---|---|
| `templates/ecr.tf` | ECR repositories (app + nginx) |
| `templates/iam.tf` | IAM Task Execution Role, IAM Task Role |
| `templates/service.tf` | CloudWatch Log Group, Security Group, ECS Task Definition, ECS Service |
| `templates/target-group.tf` | ALB Target Group |
| `templates/alb-rule.tf` | ALB Listener Rule (host-header routing) |

---

## Cấu trúc repo

```
Terraform-template/
├── templates/                  # CI/CD copy vào working dir khi cần
│   ├── iam.tf                  # IAM roles (Execution Role + Task Role)
│   ├── ecr.tf                  # ECR repos
│   ├── service.tf              # ECS Task + Service + SG + CloudWatch
│   ├── target-group.tf         # ALB Target Group
│   └── alb-rule.tf             # ALB Listener Rule
│
├── locals.tf                   # Core: giá trị tính toán từ manifest + variables
├── variables.tf                # Core: input variables
├── backend.tf                  # Core: S3 remote state (partial config)
├── providers.tf                # Core: AWS provider
│
├── manifest.json               # Per-app: khai báo services, IAM policies
└── examples/
    └── terraform.tfvars.example
```

---

## CI/CD Flow

### Bước 1 — Tạo ECR repositories (lần đầu deploy)

```bash
# Working dir chứa: core files + ecr.tf + iam.tf
cp backend.tf locals.tf variables.tf providers.tf manifest.json ./terraform/
cp templates/ecr.tf templates/iam.tf ./terraform/

terraform -chdir=terraform init \
  -backend-config="bucket=gotit-terraform-state" \
  -backend-config="key=${APP_NAME}/${ENV}/terraform.tfstate" \
  -backend-config="region=ap-southeast-1" \
  -backend-config="dynamodb_table=terraform-state-lock"

terraform -chdir=terraform apply -auto-approve \
  -var="app_name=${APP_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="env=${ENV}"

# Đọc ECR URLs từ output
APP_REPO_URL=$(terraform -chdir=terraform output -raw ecr_repository_urls | jq -r '.app')
NGINX_REPO_URL=$(terraform -chdir=terraform output -raw ecr_repository_urls | jq -r '.nginx')
```

### Bước 2 — Build & Push Docker images

```bash
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin ${APP_REPO_URL}

docker build -t ${APP_REPO_URL}:${IMAGE_TAG} .
docker push ${APP_REPO_URL}:${IMAGE_TAG}

docker build -t ${NGINX_REPO_URL}:latest ./nginx
docker push ${NGINX_REPO_URL}:latest
```

### Bước 3 — Deploy ECS service

```bash
# Working dir chứa: core files + service.tf + target-group.tf + alb-rule.tf
cp templates/service.tf templates/target-group.tf templates/alb-rule.tf ./terraform/

terraform -chdir=terraform apply -auto-approve \
  -var="app_name=${APP_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="env=${ENV}" \
  -var="image_tag=${IMAGE_TAG}" \
  -var="app_repository_url=${APP_REPO_URL}" \
  -var="nginx_repository_url=${NGINX_REPO_URL}" \
  -var="vpc_id=${VPC_ID}" \
  -var="private_subnet_ids=[\"${SUBNET_A}\",\"${SUBNET_B}\"]" \
  -var="public_subnet_ids=[\"${SUBNET_C}\",\"${SUBNET_D}\"]" \
  -var="ecs_cluster_id=${ECS_CLUSTER_ID}" \
  -var="ecs_cluster_name=${ECS_CLUSTER_NAME}" \
  -var="alb_listener_arn=${ALB_LISTENER_ARN}" \
  -var="alb_security_group_id=${ALB_SG_ID}"
```

> **Lưu ý:** Từ lần deploy thứ 2 trở đi, bước 1 bỏ qua (ECR đã tồn tại). `create_ecr: false` trong `manifest.json` để skip.

---

## manifest.json

File này nằm trong **source repo của mỗi app** (không phải trong template repo). CI/CD copy vào working dir khi deploy.

```jsonc
{
    "create_ecr": true,        // Tạo ECR repos lần đầu. Set false sau khi đã tạo.

    "services": {
        "api": {
            "is_public": false,     // false = private subnet (behind ALB)
            "port": 8080,
            "target_group": {
                "health_check": {
                    "path": "/up",
                    "interval": 30,
                    "timeout": 5,
                    "healthy_threshold": 2,
                    "unhealthy_threshold": 3
                }
            },
            "mapping": [
                {
                    "priority": 100,
                    "domain": ["api.example.com"]
                }
            ]
        },
        "worker": {
            "is_public": false,
            "port": 8080
            // Không có target_group và mapping => internal service, không expose qua ALB
        }
    },
    "iam_policies": {
        // Policy ARNs được attach vào ECS Task Role
        "s3": "arn:aws:iam::123456789:policy/s3-read-policy",
        "sqs": "arn:aws:iam::123456789:policy/sqs-consume-policy"
    }
}
```

---

## Variables quan trọng

| Variable | Required | Mô tả |
|---|---|---|
| `app_name` | ✅ | Tên app (prefix cho tất cả resources) |
| `environment` | ✅ | `stg` hoặc `prod` |
| `env` | ✅ | Short alias: `stg` / `prod` / `dev` |
| `image_tag` | Khi deploy service | Commit SHA hoặc version tag |
| `app_repository_url` | Khi deploy service | ECR URL cho app image |
| `nginx_repository_url` | Khi deploy service | ECR URL cho nginx image |
| `vpc_id` | ✅ | VPC ID |
| `private_subnet_ids` | ✅ | Private subnet IDs |
| `public_subnet_ids` | ✅ | Public subnet IDs |
| `ecs_cluster_id` | ✅ | ECS Cluster ARN |
| `alb_listener_arn` | Khi tạo ALB rules | ALB Listener ARN |
| `alb_security_group_id` | Khi deploy service | ALB Security Group ID |

---

## Ghi chú kỹ thuật

- **Launch type**: EC2 với `awsvpc` network mode → cần EC2 instances hỗ trợ ENI trunking
- **2-container pattern**: nginx (port 80) → proxy → app (port từ manifest)
- **Rolling deployment**: `min_healthy = 50%`, `max = 200%`
- **State**: S3 + DynamoDB lock, partial backend config (inject từ CI/CD)
- **IAM**: Tách `execution role` (pull image, write logs) và `task role` (AWS API calls)
