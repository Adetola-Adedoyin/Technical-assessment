# AetherPay — Multi-Region AWS ECS Infrastructure

Terraform implementation of a secure, highly available, multi-region AWS
infrastructure for AetherPay using Amazon ECS Fargate.

---

## Architecture overview

```
Internet / External Partners
          │
          ▼
    AWS Route 53
    Failover DNS routing
    Health checks every 30s
          │
    ┌─────┴──────┐
    │            │
    ▼            ▼
us-east-1    us-west-2
(PRIMARY)    (SECONDARY)
             warm standby

Each region:
  WAF Web ACL
    │
  ALB (public subnets)
    │
  ECS Fargate tasks (private app subnets)
    │
  Aurora PostgreSQL (isolated DB subnets)
```

### Regions

| Role      | Region    | VPC CIDR      | ECS tasks (normal) |
|-----------|-----------|---------------|--------------------|
| Primary   | us-east-1 | 10.24.0.0/20  | 3 (scales to 10)   |
| Secondary | us-west-2 | 10.25.0.0/20  | 2 (scales to 10)   |

### Subnet layout (per region, per AZ × 3)

| Tier              | Purpose                              | Internet route |
|-------------------|--------------------------------------|----------------|
| Public            | ALB, NAT Gateways                    | Via IGW        |
| Private app       | ECS Fargate tasks                    | None           |
| Isolated DB       | Aurora PostgreSQL                    | None           |

---

## Project structure

```
aetherpay/
├── bootstrap/          # One-time S3 state bucket + DynamoDB lock table
├── modules/
│   ├── networking/     # VPC, subnets, IGW, NAT, route tables, VPC endpoints, SGs
│   ├── security/       # IAM roles, KMS keys, Secrets Manager, WAF
│   ├── ecs/            # ECR, ECS cluster/service, ALB, autoscaling, alarms
│   ├── aurora/         # Aurora PostgreSQL Global Database
│   └── sqs/            # SQS queue + dead-letter queue
├── environments/
│   ├── primary/        # us-east-1 root module
│   └── secondary/      # us-west-2 root module
├── global/             # Route 53 hosted zone + failover routing
└── README.md
```

---

## Before you deploy

### 1. AWS credentials

Ensure your AWS CLI credentials have permissions to create:
VPC, ECS, RDS, IAM, KMS, Secrets Manager, S3, DynamoDB, Route 53, WAF, ECR, SQS, CloudWatch.

```bash
aws sts get-caller-identity   # Confirm your credentials are working
```

### 2. ACM certificates

ACM certificates are regional. You need one in each region.

```
us-east-1:
  1. Open AWS Certificate Manager → Request certificate
  2. Enter your domain (e.g. adetola.com and *.adetola.com)
  3. Choose DNS validation → Create records → Wait for Issued status
  4. Copy the certificate ARN

us-west-2:
  Repeat the same steps in the us-west-2 console
```

Paste the ARNs into `terraform.tfvars` for each environment:
```hcl
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/YOUR-CERT-ID"
```

### 3. Container image

Build and push your application image to ECR after the primary environment
is deployed. The ECR repository URL is available as a Terraform output.

```bash
# After deploying the primary environment:
cd environments/primary
terraform output ecr_repository_url

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ecr_repository_url>

# Build and push
docker build -t aetherpay:latest .
docker tag aetherpay:latest <ecr_repository_url>:latest
docker push <ecr_repository_url>:latest
```

ECR cross-region replication automatically copies the image to us-west-2.

### 4. Replace YOUR_ACCOUNT_ID

Find your AWS account ID:
```bash
aws sts get-caller-identity --query Account --output text
```

Replace `YOUR_ACCOUNT_ID` in:
- `environments/primary/versions.tf`
- `environments/secondary/versions.tf`
- `global/providers.tf`

---

## Deployment order

Follow this order exactly. Each step depends on the previous one.

### Step 1 — Bootstrap (run once only)

```bash
cd aetherpay/bootstrap
terraform init
terraform apply
```

Note the two output values — they confirm the bucket and table names.

### Step 2 — Primary environment (us-east-1)

```bash
cd environments/primary
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your real ACM certificate ARN and image URI
terraform init
terraform validate
terraform plan
terraform apply
```

After apply, note these outputs — you need them for the next steps:
```bash
terraform output aurora_global_cluster_id   # needed for secondary
terraform output alb_dns_name               # needed for global
terraform output alb_zone_id                # needed for global
terraform output ecr_repository_url         # needed to push your image
```

### Step 3 — Populate secrets

The Aurora master password is managed automatically by RDS (stored in Secrets Manager).
Populate the application secrets manually:

```bash
# Database connection details (update host after Aurora is provisioned)
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id aetherpay/primary/db-credentials \
  --secret-string '{"username":"aetherpay_admin","password":"YOUR_PASSWORD","host":"YOUR_AURORA_ENDPOINT","port":5432,"dbname":"aetherpay"}'

# Application API keys
aws secretsmanager put-secret-value \
  --region us-east-1 \
  --secret-id aetherpay/primary/app-secrets \
  --secret-string '{"api_key":"YOUR_KEY","api_secret":"YOUR_SECRET"}'
```

Repeat for the secondary environment (region us-west-2, secret IDs use `secondary`).

### Step 4 — Secondary environment (us-west-2)

```bash
cd environments/secondary
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - Set global_cluster_id to the value from Step 2
#   - Set your us-west-2 ACM certificate ARN
#   - Set the us-west-2 container image URI
terraform init
terraform validate
terraform plan
terraform apply
```

After apply, note:
```bash
terraform output alb_dns_name   # needed for global
terraform output alb_zone_id    # needed for global
```

### Step 5 — Global Route 53

```bash
cd global
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with the ALB DNS names and zone IDs from Steps 2 and 4
terraform init
terraform validate
terraform plan
terraform apply
```

After apply:
```bash
terraform output hosted_zone_name_servers
# Update your domain registrar's NS records to these four values
```

---

## Failover behaviour

### DNS failover timing

| Phase                    | Duration     | What happens                                      |
|--------------------------|--------------|---------------------------------------------------|
| Health check detection   | 90s minimum  | Route 53 polls every 30s, needs 3 failures        |
| DNS TTL drain            | up to 60s    | Cached DNS responses expire                       |
| Total worst case         | ~2.5 minutes | All clients redirected to secondary               |

### Aurora failover (manual)

Aurora Global Database replication is asynchronous. Promoting the secondary
cluster is a manual operation:

```bash
# In the AWS console: RDS → Databases → select global cluster → Actions → Remove from global
# Or via CLI:
aws rds remove-from-global-cluster \
  --region us-west-2 \
  --global-cluster-identifier aetherpay-global-cluster \
  --db-cluster-identifier aetherpay-secondary-cluster
```

After promotion, the secondary cluster becomes a standalone read/write cluster.
Update the `DB_CREDENTIALS` secret in us-west-2 to point to the new writer endpoint.

**Important**: Aurora replication does not guarantee RPO=0. Transactions that
were in-flight when the primary failed may not have been replicated.

---

## Security summary

| Control                  | Implementation                                              |
|--------------------------|-------------------------------------------------------------|
| Network isolation        | ECS tasks in private subnets, Aurora in isolated subnets    |
| No public IPs on tasks   | `assign_public_ip = false` on ECS service                   |
| AWS service traffic      | 7 VPC endpoints — no NAT Gateway for AWS API calls          |
| TLS                      | ALB enforces HTTPS, TLS 1.3 policy, HTTP→HTTPS redirect     |
| WAF                      | Rate limit (1000 req/5min), CRS, Known Bad Inputs, IP rep   |
| IAM least privilege      | Separate execution and task roles, scoped resource ARNs     |
| Secrets                  | Secrets Manager + KMS CMK, never in env vars or state       |
| Encryption at rest       | KMS CMKs for CloudWatch logs, Aurora storage, SQS, secrets  |
| Aurora SSL               | `rds.force_ssl = 1` in parameter group                      |
| ECR                      | Immutable tags, scan on push, lifecycle policy              |
| State security           | S3 versioning + encryption, DynamoDB locking                |

---

## Validation commands

Run these from each environment directory before applying:

```bash
# Format check
terraform fmt -recursive -check .

# Syntax and reference validation
terraform validate

# Preview changes (requires real AWS credentials and backend)
terraform plan
```

---

## Useful post-deployment commands

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster aetherpay-primary \
  --services aetherpay-primary \
  --region us-east-1

# Tail ECS logs
aws logs tail /ecs/aetherpay/primary --follow --region us-east-1

# Check Route 53 health check status
aws route53 get-health-check-status --health-check-id <health_check_id>

# Force ECS service redeployment (e.g. after pushing a new image)
aws ecs update-service \
  --cluster aetherpay-primary \
  --service aetherpay-primary \
  --force-new-deployment \
  --region us-east-1
```
