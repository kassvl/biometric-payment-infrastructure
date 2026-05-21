# `terraform/`

All AWS infrastructure-as-code lives here. The directory is split into three
distinct concerns so that responsibilities, blast radius, and review cadence
stay separated:

| Subdirectory   | Purpose                                                                                              |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| `bootstrap/`   | One-time, **manually applied** module that creates the S3 state bucket and DynamoDB lock table.      |
| `modules/`     | **Reusable** building blocks (VPC, EKS, RDS, Security, DNS+TLS, Observability). No remote state here.|
| `environments/`| **Composition** layer (`dev/`, `prod/`) — wires modules together with environment-specific inputs.   |

## Conventions

- **Provider versions** are pinned in `versions.tf` for every leaf module and every environment.
- **Backend** is S3 with DynamoDB locking; defined per-environment in `environments/<env>/backend.tf`.
- **Variables** never carry secrets. Secrets live in AWS Secrets Manager or SSM Parameter Store and are referenced by ARN.
- **Tags** include at minimum `Project`, `Environment`, `Owner`, `CostCenter`, and `DataClassification`.
- **Formatting** is enforced via `terraform fmt -recursive` in CI and pre-commit.
- **Validation** runs `terraform validate` plus Checkov + tfsec in CI before any plan reaches a reviewer.

## Apply order (cold-start)

```
1. bootstrap/                 (manual, one-time per AWS account)
2. environments/dev/          (vpc → security → eks → rds → observability → dns-tls)
3. environments/prod/         (same order; promoted only after dev is green)
```
