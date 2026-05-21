# `terraform/modules/eks/`

> Managed Kubernetes control plane plus the IAM scaffolding that lets every
> pod authenticate to AWS without static keys.

## What this module creates

| Resource                       | Detail                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------- |
| EKS cluster                    | Kubernetes 1.30, control-plane logging enabled (api, audit, authenticator, controllerManager, scheduler). |
| Cluster security group         | Restricts API server traffic; control-plane endpoint set to **private + restricted public CIDRs**. |
| Managed node group             | Spot or on-demand, AMI auto-updated via EKS, taints/labels for system vs app workloads.           |
| OIDC identity provider         | Required for IRSA — federates K8s service-account tokens into IAM roles.                          |
| Cluster IAM role               | Trust policy locked to `eks.amazonaws.com`, only the policies EKS itself needs.                   |
| Node IAM role                  | Minimum AmazonEKSWorkerNodePolicy + AmazonEC2ContainerRegistryReadOnly + VPC CNI policy.          |
| Core add-ons                   | `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver` — managed (auto-patched) versions.       |
| Cluster encryption provider    | KMS envelope encryption for Kubernetes secrets at rest in etcd.                                    |

## Identity model — IRSA

Every workload that needs AWS access (External Secrets, AWS Load Balancer Controller,
Cluster Autoscaler, app pods reading Secrets Manager) gets:

1. A Kubernetes ServiceAccount annotated with `eks.amazonaws.com/role-arn`.
2. An IAM role whose trust policy allows that specific service-account to assume it via OIDC.
3. **No long-lived access keys anywhere in the cluster**.

The full implementation, IAM trust-policy templates, and the
**"Mülakatta Bu Soruyu Alırsan"** Q&A section (private endpoint vs public,
why managed node groups vs Karpenter, AMI patching cadence, etcd encryption
at rest) live in the upcoming `infra(eks):` commit.
