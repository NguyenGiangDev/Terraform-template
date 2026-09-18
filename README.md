# Terraform ECS Deployment Template

Bộ Terraform template cho phép mỗi source repo tự khai báo cấu hình deploy lên ECS thông qua 1 file `manifest.json`. `locals.tf` đọc manifest đó và tự động tạo toàn bộ hạ tầng AWS cần thiết.

## Cấu trúc thư mục

```
terraform-template/              # Repo này (shared template)
├── manifest.json                ← ✏️  File duy nhất developer cần chỉnh
├── providers.tf                 ← AWS provider + required versions
├── variables.tf                 ← Tất cả input variables (inject từ CI/CD)
├── locals.tf                    ← Parse manifest.json, tính toán derived values
├── iam.tf                       ← IAM roles (execution + task) + policy attachments
├── main.tf                      ← Module calls với for_each
├── outputs.tf                   ← ARNs, IDs của resources đã tạo
├── backend.tf                   ← Remote state config (template)
│
├── modules/
│   ├── ecs-service/             ← Task Definition + ECS Service + SG + CloudWatch
│   ├── target-group/            ← ALB Target Group
│   └── alb-rule/                ← ALB Listener Rule (host-header routing)
│
└── examples/
    └── terraform.tfvars.example ← Ví dụ tfvars file cho CI/CD
```

## manifest.json — File duy nhất developer cần quan tâm

```json
{
    "services": {
        "api": {
            "is_public": false,     // false = private subnet (default), true = public subnet
            "port": 8080,           // Container port
            "target_group": {       // Tạo ALB Target Group. Naming: {app}-{service}-{port}-tg
                "health_check": {
                    "path": "/up",
                    "interval": 30,
                    "timeout": 5,
                    "healthy_threshold": 2,
                    "unhealthy_threshold": 3
                }
            },
            "mapping": [            // Tạo ALB Listener Rules (host-header routing)
                {
                    "priority": 100,
                    "domain": ["backend-rewardhub-stg.gotit.vn"]
                }
            ]
        }
    },
    "iam_policies": {               // Policy ARNs attach vào ECS Task Role
        "s3": "arn:aws:iam::890970452363:policy/s3_gotit-campaign-cdn-dev_rwdObject",
        "sqs": "arn:aws:iam::890970452363:policy/sqs_reward-hub_stg"
    }
}
```

### Các field trong manifest

| Field | Required | Default | Mô tả |
|-------|----------|---------|-------|
| `services.<name>.is_public` | ❌ | `false` | `false` = private subnet, `true` = public subnet |
| `services.<name>.port` | ❌ | `8080` | Container port |
| `services.<name>.cpu` | ❌ | var `default_cpu` | CPU units (1024 = 1 vCPU) |
| `services.<name>.memory` | ❌ | var `default_memory` | Memory MB |
| `services.<name>.desired_count` | ❌ | var `default_desired_count` | Số task instances |
| `services.<name>.target_group` | ❌ | — | Khai báo để tạo ALB Target Group |
| `services.<name>.target_group.health_check.path` | ❌ | `/up` | Health check endpoint |
| `services.<name>.mapping[].priority` | ❌ | Auto-calculate | Priority ALB rule (1–50000, unique) |
| `services.<name>.mapping[].domain` | ✅ (nếu có mapping) | — | List domains để route traffic |
| `iam_policies.<key>` | ❌ | — | Policy ARN attach vào Task Role |

> **Ghi chú về comments**: `manifest.json` hỗ trợ JS-style comments (`//`). `locals.tf` tự động strip chúng trước khi parse.

## Workflow triển khai

### Developer làm gì

1. Mở `manifest.json` trong repo
2. Khai báo services và requirements
3. Commit & push → CI/CD lo phần còn lại

### CI/CD pipeline làm gì

```bash
# 1. Checkout terraform-template
git clone https://github.com/your-org/terraform-template /tmp/tf

# 2. Copy manifest từ app repo vào terraform-template
cp ./terraform/manifest.json /tmp/tf/manifest.json

# 3. Tạo tfvars file (inject environment-specific values)
cat > /tmp/tf/terraform.tfvars << EOF
app_name    = "${APP_NAME}"
environment = "${ENV}"
vpc_id      = "${VPC_ID}"
...
alb_listener_arn = "${ALB_LISTENER_ARN}"  # Chọn ALB dựa trên environment
service_images = {
  api = "${ECR_URI}/${APP_NAME}/api:${COMMIT_SHA}"
}
EOF

# 4. Deploy
cd /tmp/tf
terraform init -backend-config="key=${APP_NAME}/${ENV}/terraform.tfstate"
terraform plan
terraform apply -auto-approve
```

## Resources được tạo tự động

Dựa trên manifest, Terraform sẽ tạo:

| Resource | Điều kiện |
|----------|-----------|
| **IAM Execution Role** | Luôn tạo (cần để pull ECR image, gửi logs) |
| **IAM Task Role** | Luôn tạo (attach policies từ `iam_policies`) |
| **CloudWatch Log Group** | Mỗi service → `/ecs/{app}/{env}/{service}` |
| **Security Group** | Mỗi service (allow từ ALB SG → container port) |
| **ECS Task Definition** | Mỗi service (EC2 launch type, awsvpc network mode) |
| **ECS Service** | Mỗi service |
| **ALB Target Group** | Service có khai báo `target_group` |
| **ALB Listener Rule** | Service có khai báo `mapping` |

## Variables cho CI/CD

| Variable | Required | Mô tả |
|----------|----------|-------|
| `app_name` | ✅ | Tên app (prefix cho resources) |
| `environment` | ✅ | `dev` / `stg` / `prod` |
| `vpc_id` | ✅ | VPC ID |
| `public_subnet_ids` | ✅ | List public subnet IDs |
| `private_subnet_ids` | ✅ | List private subnet IDs |
| `ecs_cluster_id` | ✅ | ECS Cluster ID |
| `ecs_cluster_name` | ✅ | ECS Cluster name |
| `alb_listener_arn` | ✅ | ALB Listener ARN (theo environment) |
| `alb_security_group_id` | ✅ | ALB Security Group ID |
| `service_images` | ✅ | Map `{service_name => image_uri}` |
| `default_cpu` | ❌ | Default CPU (256) |
| `default_memory` | ❌ | Default memory MB (512) |
| `default_desired_count` | ❌ | Default task count (1) |
| `service_cpu` | ❌ | Override CPU per service |
| `service_memory` | ❌ | Override memory per service |
| `service_desired_count` | ❌ | Override count per service |
| `tags` | ❌ | Additional tags |

## Ví dụ: Thêm service mới

Chỉ cần thêm vào `manifest.json`:

```json
{
    "services": {
        "api": { ... },
        "worker": {
            "is_public": false,
            "port": 8080
            // Không có target_group và mapping
            // → chỉ tạo ECS Service, không gắn vào ALB
        },
        "web": {
            "is_public": false,
            "port": 3000,
            "target_group": {
                "health_check": { "path": "/" }
            },
            "mapping": [
                {
                    "priority": 200,
                    "domain": ["rewardhub-stg.gotit.vn"]
                }
            ]
        }
    }
}
```

Sau đó thêm image vào CI/CD:
```hcl
service_images = {
  api    = "...ecr.../api:tag"
  worker = "...ecr.../worker:tag"
  web    = "...ecr.../web:tag"
}
```

Chạy `terraform apply` → Terraform tự động tạo/update resources.

## Terraform validate

```bash
terraform init
terraform validate
terraform plan -var-file="examples/terraform.tfvars.example"
```
# Terraform-template
