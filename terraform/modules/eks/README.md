# `terraform/modules/eks/`

> Managed Kubernetes control plane (EKS 1.30) plus managed node groups, the
> IRSA OIDC provider, and the four core addons. Designed so that a single
> `terraform apply` produces a cluster you can `kubectl get nodes` against
> from your laptop, with pods that can authenticate to AWS APIs through
> IRSA — no static keys anywhere in the cluster.

---

## What this module creates

| Resource                             | Detail                                                                                              |
| ------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `aws_eks_cluster.this`               | EKS 1.30 (configurable), private + public endpoint, control-plane logging on for all 5 streams.     |
| `aws_cloudwatch_log_group.cluster`   | `/aws/eks/<cluster>/cluster` — created up front so retention + KMS settings stick on first apply.   |
| `aws_iam_role.cluster`               | Trust policy locked to `eks.amazonaws.com`. `AmazonEKSClusterPolicy` + `AmazonEKSVPCResourceController`. |
| `aws_iam_role.node`                  | Trust policy locked to `ec2.amazonaws.com`. `AmazonEKSWorkerNodePolicy` + ECR readonly + `AmazonEKS_CNI_Policy` + SSM. |
| `aws_iam_openid_connect_provider.eks`| OIDC IdP for IRSA. Thumbprint fetched dynamically via `data.tls_certificate`.                       |
| `aws_iam_role.ebs_csi`               | IRSA role for the `aws-ebs-csi-driver` pod. Trust scoped to `system:serviceaccount:kube-system:ebs-csi-controller-sa`. |
| `aws_launch_template.node[*]`        | One per node group. gp3 encrypted EBS root volume + IMDSv2 required + tag propagation.              |
| `aws_eks_node_group.this[*]`         | One per entry in `var.node_groups`. References its launch template + node IAM role + subnets.       |
| `aws_eks_addon.this[*]`              | `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`. EBS CSI gets `service_account_role_arn`.  |

## File layout

```
terraform/modules/eks/
├── versions.tf                 # terraform + aws + tls providers; no provider/backend block
├── variables.tf                # 211 lines — cluster, endpoints, encryption, logging, node groups, addons
├── data.tf                     # caller / partition / region + tls_certificate for OIDC thumbprint
├── locals.tf                   # cluster_name, oidc_issuer_host, common_tags
├── iam.tf                      # cluster role, node role, EBS CSI IRSA role
├── cluster.tf                  # aws_eks_cluster + control-plane log group + OIDC provider
├── node-groups.tf              # launch templates + managed node groups via for_each
├── addons.tf                   # 4 EKS-managed addons
├── outputs.tf                  # cluster, OIDC, IAM, node groups, addons, kubeconfig command
├── terraform.example.tfvars    # Two-group example: ON_DEMAND system + SPOT app
└── README.md                   # ← you are here
```

---

## Usage

The module is consumed from an environment composition after the VPC and
security modules (so KMS keys and subnets exist):

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "security" {
  source = "../../modules/security"
  # ...
}

module "eks" {
  source = "../../modules/eks"

  project_name = "payeye"
  env          = "dev"

  cluster_version          = "1.30"
  vpc_id                   = module.vpc.vpc_id
  control_plane_subnet_ids = module.vpc.private_app_subnet_ids
  node_subnet_ids          = module.vpc.private_app_subnet_ids

  # Endpoint posture: private ON, public ON in dev. Tighten public CIDRs in prod.
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # Encryption: in prod use a dedicated cluster-secrets CMK (do not reuse rds/ebs/logs CMKs).
  cluster_encryption_kms_key_arn = null
  node_disk_kms_key_arn          = module.security.kms_key_arns["ebs"]
  cluster_log_kms_key_arn        = module.security.kms_key_arns["logs"]

  cluster_log_retention_days = 30

  node_groups = {
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      ami_type       = "AL2_x86_64"
      disk_size_gib  = 30
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      labels         = { "workload-class" = "system" }
      taints         = []
    }
  }

  extra_tags = { OnCallTeam = "platform" }
}
```

After `terraform apply`:

```bash
# Update local kubeconfig
$(terraform output -raw kubeconfig_command)
# (or run: aws eks update-kubeconfig --region eu-central-1 --name payeye-dev-eks)

kubectl get nodes
kubectl get pods -n kube-system

# Verify IRSA on the EBS CSI controller
kubectl -n kube-system describe sa ebs-csi-controller-sa | grep eks.amazonaws.com/role-arn
```

---

## Cost expectations (eu-central-1, May 2026)

| Component                                    | Hourly | Notes                                           |
| -------------------------------------------- | -----: | ----------------------------------------------- |
| EKS control plane                            | $0.10  | Flat rate per cluster.                           |
| 2 × t3.medium ON_DEMAND (system group)       | $0.083 | 2× $0.0416/hour. Spot would be ~50% cheaper.    |
| Two 30 GiB gp3 root volumes                  | ~$0.005| Most of the cost is per-GB-month, prorated.     |
| CloudWatch Logs ingest (control-plane logs)  | varies | A few MB/hour at idle; pennies/hour.            |
| **Idle cluster, no app workload**            | **~$0.20/hour** | $4.80/day if left running.                |

A 4-hour demo: roughly **$0.80** of EKS-specific cost. Add the dev VPC's
NAT Gateway (~$0.05/hour) and you're at $1 for a complete walkthrough.

`terraform destroy` on this module takes 8–12 minutes — most of it is
draining and replacing nodes during node-group deletion.

---

## Mülakatta Bu Soruyu Alırsan

A 10-question drill on EKS provisioning and IRSA.

### Q1. "Why use managed node groups instead of self-managed worker ASGs or Karpenter?"

Three reasons. **Lower operational burden** — managed node groups handle
the AMI rotation cycle, drain-and-replace orchestration, and integration
with Cluster Autoscaler out of the box. **Tighter integration with EKS** —
upgrades use `aws eks update-nodegroup-version`, which respects the cluster
version compatibility matrix. **Maturity** — a known-good default for FinTech
auditors who recognize the resource type. The trade-off is less flexibility
than self-managed (e.g., custom pre-bootstrap user-data scripts are awkward).
Karpenter is excellent for cost optimization with dynamic instance pools but
adds operator complexity and an ongoing controller pod to operate. We pick
managed node groups for the system tier and leave a Karpenter migration
open as a follow-up ADR if the workload mix justifies it.

### Q2. "Walk me through how IRSA works end-to-end."

Five-step flow:

1. **Cluster creates an OIDC issuer** at `oidc.eks.<region>.amazonaws.com/id/<cluster-id>`.
   It hosts a JWKS document and JWT signing keys.
2. **We register that issuer as an IAM Identity Provider** (`aws_iam_openid_connect_provider`).
   IAM now trusts JWTs signed by the cluster.
3. **We create an IAM role** (e.g., `ebs_csi`) whose trust policy says
   "anyone presenting a JWT signed by this OIDC issuer, with `sub` =
   `system:serviceaccount:kube-system:ebs-csi-controller-sa` and `aud` =
   `sts.amazonaws.com`, may assume me."
4. **We annotate the Kubernetes ServiceAccount** with
   `eks.amazonaws.com/role-arn = <role ARN>`. The mutating admission
   webhook (built into EKS) sees the annotation and projects the
   `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` env vars + a 1-hour
   service-account JWT into every pod that uses the SA.
5. **AWS SDK in the pod** calls `sts:AssumeRoleWithWebIdentity` with that
   JWT, gets back a 1-hour access key, and uses it. Token rotates on
   expiry without restart.

End result: each pod has a scoped, short-lived AWS credential that maps
to its ServiceAccount. There is no long-lived `aws_access_key_id` in the
cluster, in `Secret`s, or in the node IAM role.

### Q3. "Why do you fetch the OIDC thumbprint dynamically with `tls_certificate` instead of pinning a known value?"

AWS rotates the root CA the OIDC issuer's certificate chains to.
Hard-coding a thumbprint silently breaks IRSA on rotation: the IAM provider
no longer trusts the issuer's TLS, so `AssumeRoleWithWebIdentity` returns
`InvalidIdentityToken` and every IRSA-using pod loses AWS access. By
pulling the thumbprint dynamically through the `tls` provider, every
`terraform apply` re-derives the current value. The cost is one extra HTTP
fetch at plan time; the benefit is a self-healing trust chain.

### Q4. "Why is the EKS cluster SG managed by AWS instead of you?"

EKS creates a "cluster security group" automatically and attaches it to
both the control-plane ENIs and to every worker node. It carries the
egress rules the control plane needs to talk to the nodes (kubelet on
10250, etc.). Managing it ourselves would mean re-deriving rules every
EKS minor release as AWS adds features (e.g., new ports for VPC CNI prefix
delegation). The output `cluster_security_group_id` exposes it for
downstream rules — for example, the RDS module will allow ingress from
this SG on 5432 to give EKS pods database access.

### Q5. "Public endpoint with public_access_cidrs = ['0.0.0.0/0'] — defend that for prod."

I would not. In prod we tighten this to office CIDRs and on-call jumphost
ranges. The 0/0 default in this module is for the **dev portfolio** posture
where the operator runs `kubectl` from a coffee-shop laptop and the cluster
has no live customer data. Aside from the CIDR allowlist, the public
endpoint still requires a valid AWS-signed kubeconfig token, and audit logs
record every API call. For prod the proper move is: private endpoint only,
plus a Session Manager bastion EC2 with `kubectl` for break-glass, plus
CI runs from inside the VPC via OIDC-assumed IAM roles.

### Q6. "Why a launch template per node group instead of just letting EKS use its defaults?"

Three things the EKS-default-launch-template does NOT give us:

1. **Encrypted root EBS** with a chosen KMS key. EKS defaults to
   account-default EBS encryption settings, which only works because we
   configured EBS default encryption in the security module — but that's
   an account-wide singleton. A launch template makes the encryption
   intent explicit per node group and survives even if the account
   singleton is later misconfigured.
2. **IMDSv2 required**. Defaults allow IMDSv1, which is vulnerable to
   SSRF attacks that can steal the node's IAM role credentials. Setting
   `http_tokens = "required"` blocks IMDSv1 entirely.
3. **Tags on EBS volumes and ENIs** for cost allocation. Without
   `tag_specifications`, instance tags do not propagate to the underlying
   volumes — accountants will not be able to tell which node group's
   EBS bill belongs to which workload.

### Q7. "Why `ignore_changes = [scaling_config[0].desired_size]`?"

Two systems mutate `desired_size`: Cluster Autoscaler (or Karpenter, or
HPA at the indirect ASG layer) and Terraform. Without `ignore_changes`,
Terraform would see "current desired = 5, declared desired = 2" and
scale the cluster down on every apply, fighting the autoscaler. The fix
is to declare `min_size` + `max_size` (the boundaries), let Terraform
own those, and explicitly tell Terraform "I don't care what the current
desired is — that's the autoscaler's lane".

### Q8. "What does `resolve_conflicts_on_create = OVERWRITE` do, and is it safe?"

When a managed addon (like `vpc-cni`) is installed, it can already exist in
the cluster — for example, EKS bootstraps a default `vpc-cni` DaemonSet
with no addon ownership. `OVERWRITE` says "this addon now belongs to me;
overwrite any conflicting fields with the addon-managed config." The
alternative is `NONE` (fail if any field already exists) which is too
strict for a fresh install. `PRESERVE` keeps user-set fields. For a
greenfield cluster, `OVERWRITE` is correct. For a long-lived cluster
with field-level customization on the existing DaemonSet, `PRESERVE` is
safer — but then the addon is essentially unmanaged for those fields.

### Q9. "What happens if you `terraform destroy` on this module while pods are running?"

In order: `aws_eks_node_group` deletion drains and removes the EC2
instances (kubelet runs `cordon` + `drain` per node). Pods get evicted;
those with `PodDisruptionBudget`s honor them, those without are killed.
EKS deletes the addons, then the cluster. The OIDC provider, IAM roles,
KMS log group, and launch template come down on the same apply. Total
time is 8–12 minutes. Caveats: the **CloudWatch log group** has explicit
retention; if you want to keep the audit logs after destroy, wrap them
in a separate stack with a `prevent_destroy` lifecycle. Also: if
`aws-load-balancer-controller` created any externally-managed AWS
resources (ALBs, target groups), destroy will leave them orphaned —
that's why we delete those Kubernetes resources before destroying the
infrastructure stack.

### Q10. "What's missing for a real prod EKS cluster?"

Four things, in priority order.

1. **`aws-load-balancer-controller`** with IRSA — let Kubernetes Services
   create ALBs/NLBs in our VPC. Lives under `kubernetes/` (Helm release),
   not here.
2. **Cluster Autoscaler or Karpenter** — without one, `desired_size`
   stays at our declared value and capacity does not respond to load.
3. **Pod Identity instead of IRSA** — newer AWS feature, simpler trust
   chain, no OIDC provider on each cluster. Migration is per-IAM-role and
   non-breaking for callers; we'd add it as an ADR follow-up.
4. **EKS Auto Mode** (released 2024) — bundles many of the above into a
   managed package. Worth evaluating once it stabilizes; for now we want
   the explicit, demonstrable wiring this module gives.

The cluster as written here is **production-ready in shape** — every
control plane log type captured, IRSA from day one, encrypted node disks,
IMDSv2 forced, restricted IAM trust, addons managed. Adding the
controllers above turns it into a **production-running cluster**.
