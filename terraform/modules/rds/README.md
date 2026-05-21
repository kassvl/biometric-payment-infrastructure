# `terraform/modules/rds/`

> Aurora PostgreSQL Multi-AZ — the system of record for transactional payment
> and biometric-template metadata (raw biometric vectors are stored in S3 with
> SSE-KMS, only references live here).

## What this module creates

| Resource                  | Detail                                                                                            |
| ------------------------- | ------------------------------------------------------------------------------------------------- |
| Aurora PostgreSQL cluster | Engine version pinned, Multi-AZ (writer + at least one reader in a different AZ).                 |
| Cluster parameter group   | `rds.force_ssl=1`, `log_statement=ddl`, `pgaudit.log='write,ddl'`, sane timeouts.                  |
| DB subnet group           | Bound to the **private-db** subnets from the `vpc/` module — no public route.                     |
| Security group            | Ingress only from EKS node security group on 5432; no 0.0.0.0/0 anywhere.                         |
| KMS CMK                   | Customer-managed key with rotation enabled; used for storage encryption and Performance Insights. |
| IAM database authentication | Optional — operator/break-glass access via IAM token instead of static password.                |
| Automated backups         | 7-day retention in dev, **35-day in prod**; PITR enabled.                                          |
| Cluster snapshots         | Final snapshot on destroy (mandatory in prod).                                                    |
| Enhanced monitoring       | 60-second granularity in prod, IAM role for the monitoring agent.                                  |
| Performance Insights      | Enabled with KMS encryption, retention per environment policy.                                    |

## Operational notes

- **No master password in Terraform variables.** The module creates the cluster
  with `manage_master_user_password = true`, which puts the password in AWS
  Secrets Manager under a KMS-encrypted secret. Apps fetch it via External
  Secrets Operator.
- **Schema migrations** run as Kubernetes Jobs from the application repo, not from Terraform.
- **Failover testing** is documented in `docs/runbooks/db-failover.md`.

The **"Mülakatta Bu Soruyu Alırsan"** Q&A (why Aurora vs RDS PostgreSQL,
why Multi-AZ vs Aurora Global, RPO/RTO targets, encryption-in-transit
enforcement, audit logging) is in the upcoming `infra(rds):` commit.
