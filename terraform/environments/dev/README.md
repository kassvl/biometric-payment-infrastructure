# `terraform/environments/dev/`

> Development environment composition. **Cost-optimized** by default: single
> shared NAT Gateway, no VPC endpoints, AWS-managed Flow Log encryption.
> Account-level singletons (IAM password policy, default EBS encryption)
> are owned by this environment because in a single-account portfolio repo,
> dev is the only env.

---

## What this composition wires

```
                    +-----------------------------+
                    |  module "vpc"               |
                    |  - VPC 10.0.0.0/16          |
                    |  - 2 public, 2 app, 2 db    |
                    |  - 1 NAT GW (single mode)   |
                    |  - VPC Flow Logs -> CW Logs |
                    +-------------+---------------+
                                  |
                                  | vpc_id, subnets, route tables, cidr
                                  v
                    +-----------------------------+
                    |  module "security"          |
                    |  - 4 KMS CMKs               |
                    |  - WAF v2 (regional)        |
                    |  - VPC endpoints (DISABLED) |
                    |  - IAM password policy      |
                    |  - EBS default encryption   |
                    +-------------+---------------+
                                  |
                                  | kms_key_arns["ebs"], kms_key_arns["logs"]
                                  v
                    +-----------------------------+
                    |  module "eks"               |
                    |  - EKS 1.30 cluster         |
                    |  - 1 node group (2x t3.med) |
                    |  - IRSA OIDC provider       |
                    |  - 4 addons (CNI, CoreDNS,  |
                    |    kube-proxy, EBS CSI)     |
                    +-----------------------------+
```

## Files

```
terraform/environments/dev/
├── versions.tf                 # Terraform pinning + partial S3 backend
├── providers.tf                # AWS provider with default_tags
├── variables.tf                # Env-level inputs (mostly cost-optimized defaults)
├── main.tf                     # module "vpc" + module "security" wiring
├── outputs.tf                  # Re-exports VPC, KMS, WAF, endpoint outputs
├── terraform.example.tfvars    # Copy to terraform.tfvars (gitignored)
└── README.md                   # ← you are here
```

## Cost expectations (eu-central-1 prices, May 2026)

Running this composition continuously costs roughly:

| Component                                  | Monthly | Comment                                          |
| ------------------------------------------ | ------: | ------------------------------------------------ |
| 1 × NAT Gateway (single, dev)              | ~$32    | + per-GB processing if you generate egress       |
| 1 × Elastic IP (NAT-attached)              | $0      | Only unattached EIPs are charged                 |
| 4 × KMS CMK                                | ~$4     | $1/key/month + $0.03 per 10k API calls           |
| 1 × WAF WebACL + 6 rules                   | ~$11    | $5 base + $1/managed rule × 5 + $1/custom rule   |
| WAF requests                               | $0      | Nothing hits it without an ALB                   |
| EKS control plane                          | ~$73    | $0.10/hour, flat per cluster                     |
| 2 × t3.medium ON_DEMAND (system group)     | ~$60    | $0.0416/hour × 2 — switch to SPOT to save ~50%   |
| 2 × 30 GiB gp3 root volumes                | ~$5     | $0.08/GiB-month                                  |
| CloudWatch Logs (Flow Logs, WAF, EKS)      | ~$2–5   | A few GB/month at idle                           |
| **Idle total**                             | **~$190/month** | If left running.                          |

**Tearing down between demo sessions saves the bulk of this.** A 4-hour
demo with the cluster running costs roughly:

| Component                                | 4-hour demo |
| ---------------------------------------- | ----------: |
| NAT Gateway                              | $0.18       |
| EKS control plane                        | $0.40       |
| 2 × t3.medium ON_DEMAND                  | $0.17       |
| KMS, WAF, log ingest, EBS                | ~$0.20      |
| **Total**                                | **~$1**     |

50 USD AWS credit comfortably covers ~50 demo applies. The high-leverage
move for keeping the bill low is `terraform destroy` after each session.

If you want to drive the bill down further while keeping the cluster
visible, switch the system node group to `SPOT` (cuts node cost ~50%)
or set `desired_size = 1` on a single t3.small (cluster will fit but
some addons may be Pending due to capacity).

---

## Prerequisites

You need:

- **AWS credentials** for an account where you can create VPC, KMS, WAF, IAM
  resources. SSO via `aws sso login --profile <profile>` is recommended; an
  IAM user with MFA also works.
- **`terraform` CLI** ≥ 1.5 (we run on 1.9.x).
- The **bootstrap module** already applied (creates the S3 state bucket,
  DynamoDB lock table, and KMS CMK referenced by `versions.tf`). See
  `terraform/bootstrap/README.md`.

---

## First-time apply runbook

### 1. Bootstrap the remote state (one-time per AWS account)

```bash
cd terraform/bootstrap
terraform init                # local backend, no config needed
terraform plan
terraform apply
terraform output -raw backend_config_snippet   # paste-ready snippet
```

Capture the values from `terraform output`:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "State bucket: payeye-tfstate-${ACCOUNT}"
echo "Lock table:   payeye-tfstate-locks"
echo "KMS alias:    alias/payeye-tfstate"
```

### 2. Initialize the dev backend

The dev `versions.tf` uses a partial backend config — every constant is
checked in except the bucket name (which embeds the account ID). Pass it
at init:

```bash
cd ../environments/dev

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
terraform init \
  -backend-config="bucket=payeye-tfstate-${ACCOUNT}"
```

Subsequent `terraform init` runs remember the bucket from
`.terraform/terraform.tfstate` (which is gitignored — the value gets
re-derived per developer machine).

### 3. Plan

```bash
terraform plan -out=plan.tfplan
```

Expected resources on a fresh account: roughly **65 resources** — VPC + IGW +
6 subnets + EIP + NAT + 5 route tables + 6 RT associations + Flow Log group +
Flow Log IAM role + Flow Log resource + 4 KMS keys + 4 KMS aliases + WAF
log group + WAF WebACL + WAF logging config + EBS default encryption
toggle + IAM password policy + EKS cluster + 3 IAM roles (cluster, node,
EBS CSI IRSA) + ~9 IAM role policy attachments + OIDC provider + control
plane log group + 1 launch template + 1 node group + 4 EKS addons.

If the count is materially different, stop and read the plan output. Common
deltas: forgot to set `enable_vpc_endpoints = false` (adds 22 resources),
or the bootstrap KMS key isn't found (your `versions.tf` references
`alias/payeye-tfstate` — confirm it exists).

### 4. Apply

```bash
terraform apply plan.tfplan
```

First apply takes 15–20 minutes — the EKS cluster + node group is the slow piece (the cluster control plane alone is ~10 minutes).

### 5. Verify

```bash
# VPC visible
aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=payeye" \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Tags:Tags[?Key==`Name`].Value|[0]}' \
  --output table

# KMS keys
terraform output -json kms_key_aliases | jq

# WAF WebACL
aws wafv2 list-web-acls --scope REGIONAL \
  --query 'WebACLs[?starts_with(Name, `payeye-`)]' \
  --output table

# Account password policy
aws iam get-account-password-policy

# EKS — wow demo
$(terraform output -raw eks_kubeconfig_command)
kubectl get nodes
kubectl -n kube-system get pods
kubectl -n kube-system describe sa ebs-csi-controller-sa | grep eks.amazonaws.com/role-arn

# Verify IRSA flow from inside a pod
kubectl run irsa-test \
  --rm -it --restart=Never \
  --image=public.ecr.aws/aws-cli/aws-cli:2.15.0 \
  --serviceaccount=default \
  -- sts get-caller-identity
```

### 6. Tear down (between demo sessions)

```bash
terraform destroy
```

Clean teardown takes ~10–15 minutes. The slow part is EKS node group drain
(kubelet cordons and drains each node before EKS removes the EC2 instance).
If the NAT Gateway destroy stalls, that's normal — AWS waits for inflight
connections to drain.

---

## Known compromise: Flow Log encryption

VPC Flow Logs in dev are encrypted with **AWS-managed encryption**, not the
`logs` CMK created by the security module. The reason is a module-level
cycle: passing `module.security.kms_key_arns["logs"]` into `module.vpc`
would form the cycle `vpc -> security (needs vpc_id) -> kms_key_arns -> vpc`.
Terraform refuses to plan a cycle.

Three ways out, in order of cleanliness:

1. **Separate `kms` root module**: factor KMS keys into their own composition
   that runs first; both `vpc` and `security` depend on it. Best for prod.
2. **Two-stage apply in this same env**: apply with `flow_log_kms_key_arn = null`,
   then change to the security CMK and `terraform apply` again. Works but
   leaves a manual step.
3. **Accept AWS-managed encryption on Flow Logs in dev**, use option 1 in prod.

We do (3) here. AWS-managed encryption still means the data is encrypted
at rest with an AWS-rotated key — it just doesn't appear in our key
policy or our CloudTrail trail under our key ARN.

---

## Learner Lab apply (AWS Academy)

If you are running this from inside an AWS Academy Learner Lab session
(your AWS identity comes from a `voclabs` assumed role, you have ~$50 of
lab credit, region is locked to `us-east-1`), follow this runbook instead
of the default first-time apply above.

### Lab context

- The lab provides a single pre-existing IAM role called **`LabRole`**.
  Its trust policy already accepts most AWS service principals
  (`eks.amazonaws.com`, `ec2.amazonaws.com`, etc.) and it has many AWS
  managed policies attached, including all the EKS ones we need.
- `iam:CreateUser`, `iam:CreateRole`, and `iam:AttachRolePolicy` are
  generally **blocked** for the assumed `voclabs` role.
- `iam:CreateOpenIDConnectProvider` is usually **allowed** — flip it off
  later if your specific lab type rejects it.
- Lab credentials expire every ~4 hours. When `terraform plan` starts
  returning 403 on most calls, refresh from the Vocareum portal's
  "AWS Details" → "Show" page and re-run `aws configure` (or update the
  `[default]` block in `~/.aws/credentials`).

### 1. Configure AWS CLI with Lab credentials

In the Vocareum lab portal:

1. Click **Start Lab** (the button turns green when ready).
2. Click **AWS Details** → **AWS CLI** → **Show**.
3. Copy the `[default]` block.

In your terminal:

```bash
mkdir -p ~/.aws
# Paste the [default] block (with aws_access_key_id, aws_secret_access_key,
# and aws_session_token) into ~/.aws/credentials.

# Then set the region:
aws configure set region us-east-1

# Verify
aws sts get-caller-identity
# Expect "assumed-role/voclabs/user...=Your_Name"
```

### 2. Look up the Lab account ID and confirm LabRole exists

```bash
aws sts get-caller-identity --query Account --output text
# Note this number — you'll plug it into learnerlab.tfvars below.

aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `Lab`)].{Name:RoleName,Arn:Arn}' \
  --output table
# You should see at least one row named "LabRole".
```

### 3. Bootstrap the remote state

The bootstrap module assumes it can create resources in any region. In
Learner Lab, switch its region to `us-east-1` for this run:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var "region=us-east-1"
```

Three to four minutes. State bucket is now `payeye-tfstate-<lab-account-id>`
in `us-east-1`.

### 4. Wire up the dev composition for the Lab

```bash
cd ../environments/dev

# Copy the committed example to the gitignored real tfvars file.
cp learnerlab.example.tfvars learnerlab.tfvars

# Replace the placeholder account ID (339713122678) with YOUR Lab's ID
# in BOTH eks_cluster_iam_role_arn and eks_node_iam_role_arn.
ACCT=$(aws sts get-caller-identity --query Account --output text)
sed -i.bak "s/339713122678/${ACCT}/g" learnerlab.tfvars
rm learnerlab.tfvars.bak

# The dev backend versions.tf hard-codes region eu-central-1 — override at init.
terraform init -reconfigure \
  -backend-config="bucket=payeye-tfstate-${ACCT}" \
  -backend-config="region=us-east-1"
```

### 5. Plan + apply

```bash
terraform plan -var-file=learnerlab.tfvars -out=lab.tfplan
# Review the plan. Expected: 60-65 resources but NO IAM role creates for
# the cluster role, the node role, or the EBS CSI IRSA role (they're
# either reused or skipped).

terraform apply lab.tfplan
# 15-20 minutes for the EKS cluster + node group.
```

### 6. Wow demo

```bash
$(terraform output -raw eks_kubeconfig_command)
kubectl get nodes
kubectl -n kube-system get pods
```

### 7. Tear down BEFORE the lab session ends

The lab auto-stops after a few hours and you may lose the ability to
destroy with the same credentials. Make a habit of:

```bash
terraform destroy -var-file=learnerlab.tfvars
```

10-15 minutes. Confirms cluster, node group, NAT, EIP, KMS keys, WAF, VPC
gone. The S3 state bucket and DynamoDB lock table from `bootstrap/` survive
across sessions — that is intentional.

---

## What this composition does NOT do (yet)

- **No RDS, no application workloads.** They land in subsequent commits — first
  the RDS module (Aurora PostgreSQL Multi-AZ), then app deployments under
  `kubernetes/`.
- **No `aws-load-balancer-controller`, no Argo CD, no GitOps wiring.** Those
  are kubernetes-side concerns; once the cluster exists they go in
  `kubernetes/workloads/` and `kubernetes/external-secrets/`.
- **No GuardDuty / Security Hub / CloudTrail / AWS Config.** These are the
  account-baseline / threat-detection layer; they ship in a follow-up
  `infra(security): account-baseline` commit.

When those modules land, this composition's `main.tf` grows by a few more
`module "..."` blocks and the inputs flow through the same pattern.
