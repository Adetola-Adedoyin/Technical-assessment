# Part 4 — CI/CD Pipeline and Drift Detection

## Workflow overview

```
Pull Request (Terraform changes)
  └─► terraform-plan.yml
        ├─ lint job      : fmt check + TFLint (whole repo, once)
        ├─ security job  : Trivy IaC scan (CRITICAL/HIGH → fail)
        └─ plan job (×3) : init → validate → plan → upload artifact → PR comment
              primary   [concurrency: tf-state-primary]
              secondary [concurrency: tf-state-secondary]
              global    [concurrency: tf-state-global]

Merge to main → manual trigger
  └─► terraform-apply.yml
        └─ verify-and-apply job
              ├─ Verify commit SHA matches input
              ├─ Download exact plan artifact from PR run
              ├─ terraform show  (pre-apply review)
              └─ terraform apply tfplan.binary
              [concurrency: tf-state-<env>, environment: production (manual approval)]

Daily 06:00 UTC (or manual)
  └─► terraform-drift.yml
        ├─ drift job (×3) : init → plan -detailed-exitcode → report
        │     primary   [concurrency: tf-state-primary]
        │     secondary [concurrency: tf-state-secondary]
        │     global    [concurrency: tf-state-global]
        └─ notify job     : Slack alert if drift or error detected
```

---

## 1. How the workflows operate

### terraform-plan.yml (PR validation)

Triggered by any pull request to `main` that modifies files under `aetherpay/`.

- `lint` job: runs `terraform fmt -check -recursive` and TFLint against all three environments. Fails immediately on any formatting or lint error.
- `security` job: runs Trivy in IaC config mode across the `aetherpay/` directory. Fails on CRITICAL or HIGH severity findings.
- `plan` job (matrix — primary, secondary, global): runs after lint and security pass. Initialises Terraform, validates, generates a binary plan, uploads it as an artifact named `tfplan-<env>-<sha>`, and posts the human-readable plan as a PR comment.

### terraform-apply.yml (deployment)

Triggered manually (`workflow_dispatch`) from the Actions tab after a PR is merged.

Inputs required:
- `environment` — which environment to deploy (`primary`, `secondary`, or `global`).
- `plan_run_id` — the Actions run ID from the PR validation run that produced the approved plan.
- `expected_sha` — the exact git commit SHA the plan was generated from.

The workflow checks out that exact commit, verifies the SHA, downloads the binary plan artifact, shows it, then applies it. No new plan is generated.

### terraform-drift.yml (scheduled detection)

Runs daily at 06:00 UTC and on manual dispatch. Runs `terraform plan -detailed-exitcode` for each environment. Exit codes are interpreted as:

| Exit code | Meaning |
|-----------|---------|
| `0` | No changes — infrastructure matches state |
| `1` | Terraform execution error |
| `2` | Drift detected — infrastructure differs from state |

Drift is reported in the GitHub Actions step summary and uploaded as an artifact. A Slack notification is sent if `SLACK_DRIFT_WEBHOOK_URL` is configured. Drift is **never** automatically corrected.

---

## 2. AWS OIDC authentication

GitHub Actions authenticates to AWS using OpenID Connect (OIDC). No long-lived access keys are stored anywhere.

### How it works

1. GitHub's OIDC provider issues a short-lived JWT token for each workflow run.
2. The workflow exchanges that token for temporary AWS credentials by assuming an IAM role.
3. Credentials are scoped to the duration of the job and automatically expire.

### IAM Identity Provider setup (one-time)

In the AWS console, go to IAM → Identity Providers → Add provider:

```
Provider type : OpenID Connect
Provider URL  : https://token.actions.githubusercontent.com
Audience      : sts.amazonaws.com
```

### IAM role trust policy

Create an IAM role (e.g. `aetherpay-github-actions-terraform`) with this trust policy.
Replace the placeholders with your actual values.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<YOUR_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:*"
        }
      }
    }
  ]
}
```

To restrict to only the `main` branch for apply operations, change the `sub` condition to:

```
"repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:ref:refs/heads/main"
```

---

## 3. Required IAM permissions

The IAM role needs permissions to read/write Terraform state and to manage the infrastructure resources. Follow least-privilege — scope each permission to the specific resources.

### Minimum permissions for plan and drift detection (read-only)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": [
        "arn:aws:s3:::aetherpay-terraform-state-<YOUR_ACCOUNT_ID>",
        "arn:aws:s3:::aetherpay-terraform-state-<YOUR_ACCOUNT_ID>/*",
        "arn:aws:dynamodb:us-east-1:<YOUR_ACCOUNT_ID>:table/aetherpay-terraform-locks"
      ]
    },
    {
      "Sid": "ReadInfrastructure",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ecs:Describe*",
        "ecs:List*",
        "rds:Describe*",
        "route53:Get*",
        "route53:List*",
        "elasticloadbalancing:Describe*",
        "sqs:GetQueueAttributes",
        "sqs:ListQueues",
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:ListRolePolicies",
        "kms:DescribeKey",
        "secretsmanager:DescribeSecret",
        "wafv2:GetWebACL",
        "wafv2:ListWebACLs"
      ],
      "Resource": "*"
    }
  ]
}
```

For apply operations, add write permissions scoped to the AetherPay resources (e.g. `ec2:CreateVpc`, `ecs:UpdateService`, etc.). Scope by resource ARN prefix where possible.

---

## 4. Required GitHub secrets and variables

Configure these in your repository under Settings → Secrets and variables → Actions.

### Variables (non-sensitive)

| Name | Value | Used by |
|------|-------|---------|
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::<YOUR_ACCOUNT_ID>:role/aetherpay-github-actions-terraform` | All workflows |

### Secrets (sensitive)

| Name | Description | Used by |
|------|-------------|---------|
| `SLACK_DRIFT_WEBHOOK_URL` | Incoming webhook URL for your Slack channel. If absent, the Slack step is skipped. | terraform-drift.yml |

`GITHUB_TOKEN` is provided automatically by GitHub Actions — no configuration needed.

### GitHub Environment

Create an environment named `production` under Settings → Environments:

- Add required reviewers (the people who must approve before apply runs).
- Optionally restrict to the `main` branch only.

---

## 5. Pull request validation

When a PR is opened or updated with changes to `aetherpay/**`:

1. `lint` job runs `terraform fmt -check -recursive` — fails if any file is not formatted.
2. `lint` job runs TFLint for each environment — fails on lint errors.
3. `security` job runs Trivy — fails on CRITICAL or HIGH IaC findings.
4. `plan` job (only after lint and security pass) runs `terraform init` and `terraform validate` for each environment, then generates a binary plan.
5. The human-readable plan is posted as a comment on the PR so reviewers can see exactly what will change.
6. The binary plan artifact is uploaded with the name `tfplan-<env>-<commit-sha>` and retained for 7 days.

The PR cannot be merged (if branch protection is configured) until all jobs pass.

---

## 6. Production deployment approval

After a PR is merged to `main`:

1. A team member goes to Actions → Terraform Apply (Deploy) → Run workflow.
2. They enter:
   - `environment`: the environment to deploy.
   - `plan_run_id`: the run ID from the PR validation run (visible in the Actions URL).
   - `expected_sha`: the commit SHA the plan was generated from (the merge commit or the PR head SHA).
3. The workflow requests approval from the reviewers configured in the `production` GitHub Environment.
4. A reviewer approves in the GitHub UI.
5. The workflow proceeds.

---

## 7. How the exact reviewed plan is applied

The apply workflow never generates a new plan. It:

1. Checks out the exact commit SHA provided as input.
2. Verifies the checked-out SHA matches the input — aborts if they differ.
3. Downloads the artifact `tfplan-<env>-<sha>` from the specified plan run ID.
4. Verifies the binary file exists.
5. Runs `terraform show tfplan.binary` so the approver can see the plan one final time.
6. Runs `terraform apply tfplan.binary` — applies exactly what was reviewed.

The artifact name encodes both the environment and the commit SHA, so a plan from a different commit or environment cannot be accidentally applied.

### Limitation

GitHub Actions artifacts are not cryptographically signed. The protection here is:
- The artifact name includes the commit SHA.
- The workflow verifies the checked-out SHA matches the input SHA.
- The `production` environment gate requires a human to approve before apply runs.
- Only users with write access to the repository can trigger `workflow_dispatch`.

This is the standard approach for Terraform CI/CD on GitHub Actions at an intermediate level.

---

## 8. Scheduled drift detection

The drift workflow runs at 06:00 UTC every day and can also be triggered manually.

For each environment (primary, secondary, global):

1. Authenticates to AWS via OIDC.
2. Runs `terraform init`.
3. Runs `terraform plan -detailed-exitcode -refresh=true`.
4. Interprets the exit code:
   - `0`: writes "No drift detected" to the step summary.
   - `2`: writes the full plan diff to the step summary, uploads a drift report artifact (retained 14 days).
   - `1`: marks the job as failed and writes the error output.
5. If any environment has drift (exit code `2`) or an error (exit code `1`), the `notify` job sends a Slack message with a link to the run. The notify condition checks `needs.drift.result == 'failure'` (covers errors) and `needs.drift.outputs.drift_detected == 'true'` (covers drift).

Drift is **never** automatically corrected. The report is informational only.

---

## 9. How to test the workflows safely

### Test PR validation (no infrastructure changes)

1. Create a branch: `git checkout -b test/cicd-validation`
2. Make a trivial Terraform change, e.g. add a comment to `aetherpay/environments/primary/variables.tf`.
3. Open a PR to `main`.
4. Observe the `lint`, `security`, and `plan` jobs run.
5. Check the PR comment for the plan output.
6. Close the PR without merging — no infrastructure is changed.

To test a formatting failure: introduce a formatting error (misaligned `=`) and verify the `lint` job fails.

### Test drift detection manually

1. Go to Actions → Terraform Drift Detection → Run workflow.
2. The workflow runs against the real AWS state but does not modify anything.
3. If infrastructure matches state, all jobs show exit code `0`.
4. Review the step summary for each environment.

### Test the apply workflow (without applying)

You can verify the artifact download and SHA verification steps without running apply by:

1. Commenting out the `terraform apply` step temporarily in a test branch.
2. Running the workflow with a valid `plan_run_id` and `expected_sha`.
3. Confirming the artifact is downloaded and the SHA check passes.
4. Reverting the change before merging.

Do not run the apply workflow against production unless you intend to deploy.

---

## 10. Troubleshooting common failures

### `terraform fmt -check` fails

Run `terraform fmt -recursive` locally in the `aetherpay/` directory, commit the result.

### TFLint fails

Run `tflint --chdir=aetherpay/environments/primary` locally. Check `.tflint.hcl` if a rule needs to be disabled with justification.

### Trivy fails

Review the finding in the job log. If it is a false positive, add a `.trivyignore` file with the CVE ID and a comment explaining why it is accepted.

### OIDC authentication fails (`Error assuming role`)

- Verify the IAM Identity Provider URL is exactly `https://token.actions.githubusercontent.com`.
- Verify the trust policy `sub` condition matches your repository path.
- Verify `AWS_OIDC_ROLE_ARN` is set as a repository variable (not a secret).
- Check that `id-token: write` permission is present in the workflow.

### Plan artifact not found during apply

- Confirm the `plan_run_id` matches the run that produced the plan (check the URL in Actions).
- Confirm the `expected_sha` matches the commit SHA used in the plan run.
- Artifacts expire after 7 days — re-run the PR validation if the artifact has expired.

### Drift detection shows exit code 1

This is a Terraform execution error, not drift. Check the job log for the error message. Common causes: expired AWS credentials, backend connectivity issues, or a provider version mismatch.

### Slack notification not sent

Verify `SLACK_DRIFT_WEBHOOK_URL` is configured as a repository secret. The step is silently skipped if the secret is empty.
