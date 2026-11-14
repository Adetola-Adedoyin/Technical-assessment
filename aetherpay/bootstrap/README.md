# AetherPay Bootstrap

This configuration creates the remote state backend resources that all other
AetherPay Terraform environments depend on.

## What it creates

- An S3 bucket for storing Terraform state files (versioned, encrypted, private)
- A DynamoDB table for Terraform state locking

## When to run this

Run this **once**, before deploying any other environment (primary, secondary, global).

## Prerequisites

AWS credentials with permissions to create:
- S3 buckets and bucket policies
- DynamoDB tables

## Steps

```bash
cd bootstrap/
terraform init
terraform apply
```

After apply, note the two output values:
- `state_bucket_name`
- `dynamodb_lock_table_name`

These values are already pre-filled in the backend blocks of each environment.
If your account ID differs, update the bucket name in each environment's
`versions.tf` backend block.

## Important

This configuration uses **local state** intentionally. Do not delete the
`terraform.tfstate` file it produces. That file is how Terraform knows these
backend resources already exist.

Do not run `terraform destroy` on this configuration unless you have migrated
all environment state files elsewhere first.
