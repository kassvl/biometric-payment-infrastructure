# First successful apply — proof artifacts

**Date**: 2026-05-21
**Environment**: AWS Academy Learner Lab
**AWS Account**: `339713122678` (lab-scoped, ephemeral)
**Region**: `us-east-1`
**Cluster**: `payeye-dev-eks`
**Apply duration**: ~25 minutes (with 2 retries due to Learner Lab IAM constraints)

This directory captures the AWS-side and Kubernetes-side state of the
PayEye dev environment immediately after `terraform apply` completed
successfully. Used as **interview proof** that the infrastructure was
not just written — it was actually provisioned and verified.

## File map

| File                                  | What it shows                                                      |
| ------------------------------------- | ------------------------------------------------------------------ |
| `01-nodes.txt`                        | `kubectl get nodes -o wide` — 2 nodes Ready in 2 AZs               |
| `02-pods-all.txt`                     | `kubectl get pods -A` — 10 system pods Running (CoreDNS, CNI, kube-proxy, EBS CSI controller + node DaemonSet) |
| `03-serviceaccounts.txt`              | All ServiceAccounts in kube-system, including `ebs-csi-controller-sa` |
| `04-eks-cluster.txt`                  | EKS cluster status ACTIVE, 1.30, all 5 control-plane log types ON  |
| `05-nodegroup.txt`                    | Node group details (t3.medium ON_DEMAND, scaling 2-4)              |
| `06-addons.txt`                       | 4 EKS-managed addons installed                                      |
| `07-kms.txt`                          | 5 KMS keys (4 dev CMKs + 1 tfstate)                                 |
| `08-vpc.txt`                          | VPC + 6 subnets (3-tier × 2 AZ)                                     |
| `09-waf.txt`                          | WAF v2 WebACL with 6 rules in cost-aware priority order             |
| `10-irsa-status.txt`                  | EBS CSI SA — no IRSA annotation (Lab mode, falls back to node IAM)  |
| `11-tf-outputs.json`                  | Full `terraform output -json` capture                               |
| `12-eks-control-plane-logs.txt`       | CloudWatch log streams from EKS control plane (api, audit, scheduler, etc.) |

## Compromises in this apply (Lab-specific)

The Learner Lab `voclabs` role blocks several IAM operations. The module
was extended to handle these gracefully via flag-controlled escape hatches.
For this apply, the following dev-default behaviors were turned off:

| Compromise                                             | Reason                                                     |
| ------------------------------------------------------ | ---------------------------------------------------------- |
| Cluster + node IAM roles use `LabRole` (pre-existing)  | `iam:CreateRole` blocked.                                  |
| EBS CSI driver runs without IRSA, uses node IAM         | `iam:CreateRole` blocked for the IRSA role.                |
| OIDC IAM Identity Provider not created                  | `iam:CreateOpenIDConnectProvider` blocked.                 |
| Node EBS volumes encrypt with AWS-managed key, not CMK  | Our CMK policy needs an extra `kms:CreateGrant` statement. |
| VPC Flow Logs disabled                                  | Service-linked role requires `iam:CreateRole`.             |
| Account password policy + EBS default encryption off    | Account-wide singletons; out of scope for Lab.             |

In a non-restricted account these would all stay on by default.

## Cost incurred during this apply

- Bootstrap: ~$0.05 (KMS + S3 + DynamoDB, prorated)
- Dev composition (idle): ~$0.25 / hour
- Total for ~30 minutes of demo: well under $1

`terraform destroy` followed once screenshots were captured.

## How to read these alongside the README

The high-level repo `README.md` describes the *target* architecture. These
proofs show the *actual* state of one apply against that architecture.
Where the Lab compromises differ from the target (encrypted-with-CMK vs
encrypted-with-AWS-default, IRSA vs node IAM), the gap is documented in
both `terraform/modules/eks/README.md` and `terraform/environments/dev/README.md`
under the "Restricted-IAM environments" / "Learner Lab apply" sections.
