# `terraform/environments/prod/`

> Production environment composition. Customer-facing, regulated, audited.
> **Reliability and compliance first**, cost second.

## Backend

```hcl
# backend.tf (committed)
terraform {
  backend "s3" {
    bucket         = "payeye-tfstate-<account-id>"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "payeye-tfstate-locks"
    encrypt        = true
    kms_key_id     = "alias/payeye-tfstate"
  }
}
```

## Posture

| Area              | Setting                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------ |
| Multi-AZ          | Enforced everywhere — RDS Multi-AZ, NAT GW per AZ, EKS node group across both AZs.               |
| Backup retention  | Aurora 35 days + monthly long-term snapshot pushed to a dedicated S3 vault.                      |
| Log retention     | VPC FL / WAF: 365 days CloudWatch, then archived. CloudTrail: 7 years with object-lock.          |
| EKS control plane | Private endpoint enabled, public endpoint **CIDR-restricted** to office + on-call jumphost ranges. |
| Node groups       | On-demand for system workloads, mixed on-demand + spot for stateless app workloads.              |
| Disaster recovery | Warm standby in `eu-west-1` (Ireland). RTO target: 1 hour. RPO target: 5 minutes (Aurora cross-region replica). |

## Promotion process

1. PR opened against `prod/` with version-bumped module references (or input changes).
2. CI runs `terraform plan` and posts the diff in the PR.
3. Required reviewers: 1× DevOps engineer + 1× Security engineer.
4. Merge triggers `terraform apply` via GitHub Actions OIDC role with **manual approval** gate.
5. Apply output is archived to the long-term log S3 bucket for the audit trail.

## What can change without re-applying Terraform

- Application image tags (handled by Argo CD / GitOps from the app repos).
- Grafana dashboards and Prometheus rules (the `monitoring/` directory).
- Kubernetes namespace-level configuration via `kubernetes/`.
