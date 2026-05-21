# `terraform/modules/`

Reusable Terraform modules. Each module is **self-contained** (its own
`variables.tf`, `outputs.tf`, `versions.tf`, `README.md`) and is consumed by
one or more environment compositions in `terraform/environments/`.

## Modules

| Module           | Responsibility                                                                                       |
| ---------------- | ---------------------------------------------------------------------------------------------------- |
| `vpc/`           | VPC with 3-tier subnets (public / private-app / private-db) across 2 AZs, NAT GW per AZ, Flow Logs.  |
| `eks/`           | EKS cluster (1.30), managed node groups, IRSA OIDC provider, core add-ons (CoreDNS, kube-proxy, VPC CNI). |
| `rds/`           | Aurora PostgreSQL Multi-AZ, KMS-encrypted, parameter group hardening, automated backups, snapshots.  |
| `security/`      | Security groups, GuardDuty, Security Hub, AWS WAF v2, KMS keys, IAM password policy.                 |
| `dns-tls/`       | Route 53 hosted zones, ACM wildcard cert (DNS-validated, auto-renewing), health checks.              |
| `observability/` | CloudWatch log groups, metric filters, dashboards, SNS topics, CloudWatch alarms.                    |

## Module contract

Every module in this directory follows the same minimum interface:

- `variables.tf` — typed inputs with validation blocks where useful (e.g., CIDR shape, env name).
- `outputs.tf` — only attributes consumers actually need; **no `sensitive = false` for ARNs that grant access**.
- `versions.tf` — pinned `terraform` and `aws` provider versions.
- `README.md` — what it creates, how to use it, gotchas, and an interview Q&A section.
- No hard-coded account IDs, region names, or environment names. Everything is a variable.
- No remote backend in module source — backends are configured at the environment level.
