# Terraform Remediation — Snippet B

Snippet B configures an ECS Fargate service that depends on an ElastiCache
Redis cluster. Four Terraform configuration problems were identified. Each is
documented below with an explanation of the issue and the corrected approach.

---

## Problem 1 — Incorrect Redis endpoint and missing provisioning dependency

### Issue

The ECS task definition constructs the Redis hostname manually as a string
interpolation:

```hcl
environment = [
  {
    name  = "REDIS_HOST"
    value = "${aws_elasticache_cluster.redis.cluster_id}.abc123.cfg.use1.cache.amazonaws.com"
  }
]
```

This has two problems. First, the hostname is partially hardcoded — the
`.abc123.cfg.use1.cache.amazonaws.com` suffix is invented and will not match
the actual endpoint AWS assigns. Second, because the task definition references
`aws_elasticache_cluster.redis.cluster_id` (an ID attribute) rather than the
endpoint attribute, Terraform does not establish a dependency between the task
definition and the Redis cluster being fully provisioned. If the cluster is
created in the same `terraform apply` run, the task definition may be created
before the endpoint is available.

### Corrected approach

Reference the actual endpoint attribute that ElastiCache exposes
(`cache_nodes[0].address`). This gives Terraform the correct hostname and
also creates an implicit dependency, ensuring the cluster is fully provisioned
before the task definition is created.

```hcl
environment = [
  {
    name  = "REDIS_HOST"
    value = aws_elasticache_cluster.redis.cache_nodes[0].address
  },
  {
    name  = "REDIS_PORT"
    value = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port)
  }
]
```

Because `cache_nodes[0].address` is a known output attribute of the
`aws_elasticache_cluster` resource, Terraform automatically understands that
the task definition depends on the cluster and will sequence the operations
correctly.

---

## Problem 2 — desired_count conflicting with Application Auto Scaling

### Issue

The ECS service sets a static `desired_count`:

```hcl
resource "aws_ecs_service" "app" {
  desired_count = 2
  # ...
}
```

When Application Auto Scaling is also configured for the same service, it
manages `desired_count` at runtime. Every subsequent `terraform plan` will
show a diff because Terraform sees the current count (which Auto Scaling has
changed) and wants to reset it to `2`. Running `terraform apply` will override
the autoscaler's decision and reset the task count, potentially causing
unnecessary task churn or a brief reduction in capacity.

### Corrected approach

Add a `lifecycle` block to the ECS service that tells Terraform to ignore
changes to `desired_count`. This allows Auto Scaling to manage the count freely
at runtime while Terraform continues to manage all other service attributes.

```hcl
resource "aws_ecs_service" "app" {
  desired_count = var.ecs_desired_count  # Used only on initial creation

  lifecycle {
    # Auto Scaling manages desired_count at runtime.
    # Ignoring it here prevents Terraform from overriding the autoscaler.
    ignore_changes = [desired_count]
  }
}
```

The `desired_count` value is still useful — it sets the initial task count
when the service is first created. After that, Auto Scaling takes over and
Terraform leaves it alone.

---

## Problem 3 — ECS tasks in public subnets with public IP addresses

### Issue

The ECS service network configuration places tasks in public subnets and
assigns them public IP addresses:

```hcl
network_configuration {
  subnets          = var.public_subnet_ids
  assign_public_ip = true
}
```

### Security risk and explanation

Placing application containers in public subnets with public IPs means each
task is directly reachable from the internet on any port allowed by its
security group. This bypasses the ALB and WAF entirely for direct connections.
It also means the task's ENI is exposed to internet-based port scanning and
attack attempts. For a payment application like AetherPay, this is a
significant exposure.

The correct architecture places ECS tasks in private subnets. Inbound traffic
arrives via the ALB (which sits in the public subnets). Outbound traffic from
tasks reaches the internet via NAT Gateways, or reaches AWS services via VPC
endpoints — neither of which requires a public IP on the task itself.

### Corrected approach

```hcl
network_configuration {
  subnets          = var.private_app_subnet_ids  # Private subnets — no internet route
  security_groups  = [var.ecs_tasks_security_group_id]
  assign_public_ip = false                        # Tasks must not have public IPs
}
```

---

## Problem 4 — Database password exposed as a plaintext environment variable

### Issue

The task definition passes the database password directly as a plaintext
environment variable:

```hcl
environment = [
  {
    name  = "DB_PASSWORD"
    value = var.db_password
  }
]
```

Even if `var.db_password` is marked `sensitive = true` in Terraform, the
value ends up stored in the ECS task definition in plaintext, visible in the
AWS console, in CloudTrail logs, and in the Terraform state file. Anyone with
read access to the state bucket or the ECS console can retrieve the password.

### Corrected approach

Use the ECS `secrets` block instead of `environment`. The `secrets` block
instructs the ECS agent to fetch the value from AWS Secrets Manager at task
startup and inject it as an environment variable — the plaintext value never
appears in the task definition, the state file, or Terraform outputs.

The task execution role must have `secretsmanager:GetSecretValue` permission
for the specific secret ARN (as shown in the IAM remediation in
`vulnerability-assessment.md`).

```hcl
# In the task definition container_definitions:
secrets = [
  {
    # ECS fetches this from Secrets Manager at task startup.
    # The plaintext value is never stored in the task definition or state.
    name      = "DB_PASSWORD"
    valueFrom = var.db_credentials_secret_arn
  }
]
```

To store the secret value, use the AWS CLI or console — never Terraform
variable input:

```bash
aws secretsmanager put-secret-value \
  --secret-id aetherpay/staging/db-credentials \
  --secret-string '{"password":"YOUR_REAL_PASSWORD"}'
```
