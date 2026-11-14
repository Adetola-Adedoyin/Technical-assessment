# Part 2 — Vulnerability Assessment and Terraform Remediation

## Purpose

This folder contains the deliverables for Part 2 of the AetherPay Cloud &
Infrastructure Engineer Technical Assessment. Part 2 focuses on identifying
security vulnerabilities and Terraform configuration problems in two provided
code snippets, then producing corrected versions of each.

## What the snippets address

**Snippet A** is a Terraform security group and IAM policy configuration.
It contains four security vulnerabilities: unrestricted public HTTP ingress,
unrestricted internal protocol access, unrestricted outbound traffic, and an
overly permissive IAM policy using invalid and wildcard actions.

**Snippet B** is a Terraform ECS Fargate service configuration that depends on
an ElastiCache Redis cluster. It contains four infrastructure problems: a
manually constructed Redis hostname with a missing dependency, a `desired_count`
value that conflicts with Application Auto Scaling, ECS tasks placed in public
subnets with public IP addresses assigned, and a database password exposed
directly as a plaintext environment variable.

## Folder contents

| File | Description |
|---|---|
| `README.md` | This file — overview and index |
| `vulnerability-assessment.md` | Four vulnerabilities found in Snippet A with risks and corrections |
| `terraform-remediation.md` | Four Terraform problems found in Snippet B with corrected approaches |
| `state-migration.md` | How to move an existing ElastiCache resource into a Terraform module without destroying it |
| `terraform/snippet-a-remediated.tf` | Corrected Terraform for Snippet A (security group + IAM policy) |
| `terraform/snippet-b-remediated.tf` | Corrected Terraform for Snippet B (ECS service + Redis dependency) |

## How the remediation files relate to the assessment

The documentation files explain the reasoning behind each fix at an
intermediate engineer level. The Terraform files in `terraform/` are the
corresponding corrected code — they are syntactically valid, consistent with
the existing AetherPay project conventions, and use variables wherever
environment-specific values are required. No actual secrets, account IDs, or
resource IDs are hardcoded.

The existing Part 1 files under `aetherpay/` have not been modified.
