# `kubernetes/external-secrets/`

External Secrets Operator (ESO) configuration. ESO is the bridge between
**AWS Secrets Manager** (source of truth for all secret material) and
**Kubernetes Secret** objects (consumed by pods).

## Why ESO instead of just plain Kubernetes Secrets

| Concern                         | Plain `Secret`                              | ESO + Secrets Manager                                    |
| ------------------------------- | ------------------------------------------- | -------------------------------------------------------- |
| Where the secret lives at rest  | etcd (base64, KMS-encrypted if configured)  | AWS Secrets Manager (KMS-encrypted, audited, rotatable)  |
| Rotation                        | Manual                                      | Native rotation hooks → propagated to the cluster       |
| Audit trail                     | None at the secret level                    | CloudTrail records every read                            |
| Disaster recovery               | Re-create from runbook                      | Replicated with the secrets store                        |
| Risk of accidental Git commit   | High (someone exports the manifest)        | Low (only `ExternalSecret` references are committed)     |

## Identity flow (IRSA)

```
ServiceAccount (eso-controller)
    │   annotation: eks.amazonaws.com/role-arn = arn:aws:iam::<acct>:role/biopay-eso
    ▼
IAM Role (biopay-eso)
    │   trust:    sts:AssumeRoleWithWebIdentity from cluster OIDC issuer
    │   policy:   secretsmanager:GetSecretValue on arn:aws:secretsmanager:...:secret:biopay/<env>/*
    ▼
AWS Secrets Manager
```

No long-lived AWS access keys in the cluster. ESO assumes the role per request.

## Resources in this directory

| File                          | Purpose                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------- |
| `helm-release.yaml`           | ESO Helm chart values; pinned chart version, resource requests, replica count. |
| `cluster-secret-store.yaml`   | `ClusterSecretStore` of provider `aws` pointing to Secrets Manager in our region. |
| `service-account.yaml`        | IRSA-annotated ServiceAccount used by ESO controllers.                           |

## What workloads put in this directory

- **Nothing per-app.** `ExternalSecret` resources for individual apps live next to
  the app's `Deployment` in `kubernetes/workloads/<app>/`. This directory is
  ESO infrastructure only.
