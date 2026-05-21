# `terraform/environments/`

Environment compositions. Each subdirectory is a Terraform **root module** that:

1. Configures the S3 backend produced by `terraform/bootstrap/`.
2. Wires together the reusable modules from `terraform/modules/` with environment-specific inputs.
3. Owns its own `terraform.tfvars` (gitignored) and `*.example.tfvars` (committed).

## Environments

| Env    | Purpose                                          | Cost posture                            | HA posture                          |
| ------ | ------------------------------------------------ | --------------------------------------- | ----------------------------------- |
| `dev/` | Daily integration target for engineers and CI.   | **Cost-optimized** (smaller nodes, single-AZ data where safe, shorter retention). | Best-effort. |
| `prod/`| Customer-facing, regulated, audited.             | **Reliability-optimized** (Multi-AZ everything, full retention, NAT per AZ).      | High availability, RTO/RPO defined. |

## Promotion model

- Code changes land in `dev/` first via PR. CI runs `terraform plan` and posts the diff in the PR.
- After dev validates (manual + automated checks), the same module versions are bumped in `prod/`.
- A separate PR for `prod/` requires Security review approval; CI runs the same scanners but with stricter policies.

## Backend

Each environment has its own S3 state key:

```
s3://biopay-tfstate-<account-id>/<env>/terraform.tfstate
```

State files are versioned and encrypted with the KMS CMK created in `terraform/bootstrap/`.
DynamoDB locking is on the shared `biopay-tfstate-locks` table.
