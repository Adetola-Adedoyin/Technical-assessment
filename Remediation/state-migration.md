# State Migration — Moving Redis into a Terraform Module

This document explains how to move the existing staging ElastiCache Redis
resource into a Terraform module without destroying or recreating the actual
AWS resource.

**Important:** Moving a resource address in Terraform state only updates
Terraform's internal tracking record. It does not touch, restart, modify, or
recreate the actual AWS resource. The ElastiCache cluster continues running
uninterrupted throughout this process.

---

## Current and target addresses

| | Address |
|---|---|
| Current | `aws_elasticache_cluster.redis` |
| Target | `module.cache.aws_elasticache_cluster.redis` |

---

## Step 1 — Back up the Terraform state

Before making any state changes, create a backup of the current state file.
If anything goes wrong, you can restore from this backup.

```bash
# If using a local state file:
cp terraform.tfstate terraform.tfstate.backup

# If using an S3 remote backend, download a copy first:
terraform state pull > terraform.tfstate.backup
```

S3 versioning is already enabled on the AetherPay state bucket (configured in
`bootstrap/`), so a versioned copy also exists automatically. The manual
backup is an additional safety net.

---

## Step 2 — Update the Terraform configuration

Before running `terraform state mv`, update your `.tf` files so that the
module block exists and the top-level `aws_elasticache_cluster.redis` resource
is removed. Terraform needs the destination address to exist in configuration
before it can plan against it.

If you run `terraform plan` at this point (before the state move), Terraform
will show that it wants to destroy `aws_elasticache_cluster.redis` and create
`module.cache.aws_elasticache_cluster.redis`. Do not apply yet — the state
move in the next step prevents that.

---

## Step 3 — Move the state address

Run `terraform state mv` to update the state record from the old address to
the new one. This is a metadata-only operation.

```bash
terraform state mv \
  aws_elasticache_cluster.redis \
  module.cache.aws_elasticache_cluster.redis
```

Expected output:

```
Move "aws_elasticache_cluster.redis" to "module.cache.aws_elasticache_cluster.redis"
Successfully moved 1 object(s).
```

---

## Step 4 — Verify the state

Confirm that the resource now appears under the new address and that the old
address is gone.

```bash
# List all resources — confirm the new address is present
terraform state list | grep redis

# Inspect the full resource record to confirm it still holds the correct
# AWS resource ID and attributes
terraform state show module.cache.aws_elasticache_cluster.redis
```

The output of `terraform state show` should display the same cluster ID,
endpoint, and configuration that existed before the move.

---

## Step 5 — Review the Terraform plan

Run `terraform plan` to confirm that Terraform sees no changes to the Redis
resource. A clean plan (no create, update, or destroy for the Redis cluster)
confirms the migration was successful.

```bash
terraform plan
```

If the plan shows no diff for the Redis cluster, the migration is complete.
If it still shows a destroy/create, check that:
- The module block in your configuration matches the resource address exactly.
- The `aws_elasticache_cluster` resource is no longer defined at the top level.
- The state move completed without errors.

---

## Alternative approach — the `moved` block

Terraform 1.1 introduced the `moved` block as a declarative alternative to
`terraform state mv`. Instead of running a CLI command, you add a block to
your configuration:

```hcl
moved {
  from = aws_elasticache_cluster.redis
  to   = module.cache.aws_elasticache_cluster.redis
}
```

When you run `terraform plan`, Terraform detects the `moved` block and
automatically updates the state address. The plan will show the move and
confirm no resource recreation. After applying, you can remove the `moved`
block (or leave it in place — it is harmless after the move is complete).

The `moved` block is preferable for team environments because the migration
intent is recorded in version control alongside the configuration change,
rather than being a manual CLI step that may not be documented.

---

## When `terraform import` is appropriate

`terraform import` is the right tool when a resource already exists in AWS
but has no corresponding entry in the Terraform state at all — for example,
a resource that was created manually in the AWS console, or a resource whose
state was accidentally deleted.

In this migration scenario, the resource is already tracked in state under
`aws_elasticache_cluster.redis`. Using `terraform import` here would be
incorrect — it would attempt to create a second state entry for the same AWS
resource, resulting in a conflict.

Use `terraform import` when:
- The AWS resource exists but is not in state.
- You are onboarding an existing manually-created resource into Terraform management.

Use `terraform state mv` (or a `moved` block) when:
- The resource is already in state and you are reorganising addresses
  (renaming, moving into a module, or refactoring).
