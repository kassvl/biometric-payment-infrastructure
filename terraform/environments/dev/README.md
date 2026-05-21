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

| Component                         | Monthly | Comment                                   |
| --------------------------------- | ------: | ----------------------------------------- |
| 1 × NAT Gateway (single, dev)     | ~$32    | + per-GB processing if you generate egress |
| 1 × Elastic IP (NAT-attached)     | $0      | Only unattached EIPs are charged           |
| 4 × KMS CMK                       | ~$4     | $1/key/month + $0.03 per 10k API calls     |
| 1 × WAF WebACL + 6 rules          | ~$11    | $5 base + $1/managed rule × 5 + $1/custom rule |
| WAF requests                      | $0      | $0.60/million; nothing hits it without an ALB |
| CloudWatch Logs (Flow Logs, WAF)  | ~$1–3   | A few GB/month at dev volume               |
| **Idle total**                    | **~$48/month** |                                       |

**Tearing down between demo sessions saves the bulk of this.** A 4-hour demo
costs ~$0.10 in NAT-hours plus minor KMS prorations. Set
`enable_vpc_endpoints = false` (which is the default) and you save the
~$144/month worth of interface endpoint ENIs entirely.

If you want to drive the bill down further while keeping the controls visible:
- Skip the NAT entirely by also setting `enable_nat_gateway = false` upstream.
  Pods cannot egress, but the network shape is fully visible. Saves ~$32/month.

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

Expected resources on a fresh account: roughly **40 resources** — VPC + IGW +
6 subnets + EIP + NAT + 5 route tables + 6 RT associations + Flow Log group +
Flow Log IAM role + Flow Log resource + 4 KMS keys + 4 KMS aliases + WAF
log group + WAF WebACL + WAF logging config + EBS default encryption
toggle + IAM password policy.

If the count is materially different, stop and read the plan output. Common
deltas: forgot to set `enable_vpc_endpoints = false` (adds 22 resources),
or the bootstrap KMS key isn't found (your `versions.tf` references
`alias/payeye-tfstate` — confirm it exists).

### 4. Apply

```bash
terraform apply plan.tfplan
```

First apply takes 4–6 minutes — the NAT Gateway is the slow piece.

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
```

### 6. Tear down (between demo sessions)

```bash
terraform destroy
```

Clean teardown takes ~2 minutes. If it stalls on the NAT Gateway, that's
normal — AWS waits for inflight connections to drain.

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

## What this composition does NOT do (yet)

- **No EKS, no RDS, no application workloads.** They land in subsequent
  commits — first the EKS module, then RDS, then app deployments under
  `kubernetes/`.
- **No Argo CD or GitOps wiring.** That is a kubernetes-side concern; once
  the cluster exists, Argo CD goes in `kubernetes/workloads/`.
- **No GuardDuty / Security Hub / CloudTrail / AWS Config.** These are the
  account-baseline / threat-detection layer; they ship in a follow-up
  `infra(security): account-baseline` commit.

When those modules land, this composition's `main.tf` grows by a few more
`module "..."` blocks and the inputs flow through the same pattern.
