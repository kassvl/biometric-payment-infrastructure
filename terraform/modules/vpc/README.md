# `terraform/modules/vpc/`

> Network foundation. Every other module depends on this — EKS nodes land in
> private-app subnets, RDS Aurora lands in private-db subnets, ALBs sit in
> public subnets. Three-tier segmentation is the spine of the PCI-DSS
> trust boundary.

---

## What this module creates

| Resource                         | Detail                                                                                                |
| -------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `aws_vpc.main`                   | `10.0.0.0/16` (configurable), DNS hostnames + DNS support enabled, default tenancy.                   |
| `aws_internet_gateway.main`      | One per VPC.                                                                                          |
| `aws_default_security_group.main`| Default SG **stripped of all ingress and egress rules** (CIS AWS 5.4).                                |
| `aws_subnet.public[*]`           | `10.0.1.0/24`, `10.0.2.0/24` — host ALBs and NAT GWs. `map_public_ip_on_launch = false`.              |
| `aws_subnet.private_app[*]`      | `10.0.10.0/24`, `10.0.11.0/24` — host EKS nodes. Tagged for the AWS LBC.                              |
| `aws_subnet.private_db[*]`       | `10.0.20.0/24`, `10.0.21.0/24` — host Aurora, ElastiCache. **No 0.0.0.0/0 route at all.**             |
| `aws_eip.nat[*]`                 | One Elastic IP per NAT Gateway. EIPs persist across NAT replacements.                                 |
| `aws_nat_gateway.main[*]`        | **One per AZ in HA mode** (default), or one shared in `single_nat_gateway = true` (dev cost mode).    |
| `aws_route_table.public`         | One public RT for the VPC. `0.0.0.0/0 → IGW`.                                                          |
| `aws_route_table.private_app[*]` | **One private-app RT per AZ.** `0.0.0.0/0 → AZ-local NAT GW` (or shared NAT in single-NAT mode).      |
| `aws_route_table.private_db[*]`  | **One private-db RT per AZ.** Local VPC traffic only — no internet route.                              |
| Route table associations         | Every subnet associated to its tier's RT.                                                              |
| `aws_cloudwatch_log_group.flow_logs` | `/biopay/<env>/vpc/flowlogs`, configurable retention, optional KMS-CMK encryption.                |
| `aws_iam_role.flow_logs`         | Trust policy scoped to `vpc-flow-logs.amazonaws.com` with `aws:SourceAccount` + `aws:SourceArn` guards. |
| `aws_iam_role_policy.flow_logs`  | Least-privilege CloudWatch Logs write to this VPC's log group only.                                    |
| `aws_flow_log.main`              | Captures **all** traffic by default; 60-second aggregation; ARN-targeted at the log group above.       |

## File layout

```
terraform/modules/vpc/
├── versions.tf                 # Pinned terraform + aws provider (no provider/backend block)
├── variables.tf                # Typed inputs with validation
├── data.tf                     # aws_caller_identity, aws_partition, aws_region
├── locals.tf                   # Subnet maps, NAT GW map, common tags, cross-variable validation
├── main.tf                     # VPC + IGW + default SG hardening
├── subnets.tf                  # Public, private-app, private-db subnets per AZ
├── nat.tf                      # EIPs + NAT Gateways (HA or single-shared)
├── routes.tf                   # Route tables + routes + associations (per-AZ private RTs)
├── flow-logs.tf                # CloudWatch log group + IAM + flow log
├── outputs.tf                  # VPC, subnets (lists + maps by AZ), NAT IPs, RTs, flow log
├── terraform.example.tfvars    # Committed; copy to terraform.tfvars (gitignored)
└── README.md                   # ← you are here
```

---

## Usage

The module is consumed from a composing environment. Example for `dev`:

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name = "biopay"
  env          = "dev"

  cidr_block = "10.0.0.0/16"
  azs        = ["eu-central-1a", "eu-central-1b"]

  public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
  private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # dev only — switch to false for prod

  enable_flow_logs        = true
  flow_log_retention_days = 30 # 365+ in prod

  extra_tags = {
    OnCallTeam = "platform"
  }
}
```

After `terraform apply`, downstream modules consume the outputs:

```hcl
module "eks" {
  source = "../../modules/eks"

  vpc_id            = module.vpc.vpc_id
  private_subnets   = module.vpc.private_app_subnet_ids
  control_plane_subnets = module.vpc.private_app_subnet_ids
}

module "rds" {
  source = "../../modules/rds"

  vpc_id        = module.vpc.vpc_id
  db_subnet_ids = module.vpc.private_db_subnet_ids
}
```

---

## Security posture

| Control                                 | Where                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------- |
| Three-tier segmentation                 | Subnets in `subnets.tf`, route tables in `routes.tf`, no 0/0 on db RTs.                |
| Default SG hardened                     | `aws_default_security_group.main` with empty ingress/egress (CIS 5.4).                 |
| `map_public_ip_on_launch = false`       | Set on every subnet — prevents accidental public IPs on instance launches.             |
| Per-AZ NAT redundancy                   | `single_nat_gateway = false` in prod (default at the env layer).                       |
| Per-AZ private route tables             | Eliminates cross-AZ NAT data-processing fees and isolates AZ failure.                  |
| VPC Flow Logs to CloudWatch             | All traffic captured, 60-second aggregation, role-scoped via IAM trust + SourceArn.    |
| Flow Log retention                      | 30 days dev / 365+ days prod (env-level override).                                     |
| Optional KMS-CMK on log group           | `flow_log_kms_key_arn` input wires the log group to a CMK from the security module.    |
| IAM trust hardening                     | `vpc-flow-logs.amazonaws.com` trust scoped by `aws:SourceAccount` + `aws:SourceArn`.   |

---

## Trade-offs (cost-honest)

| Choice                                    | Cost impact                                                              | Why we accept it                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| NAT Gateway per AZ (prod)                 | ~$32/month per NAT × N AZs + per-GB processing                           | A single shared NAT becomes a single AZ-failure domain for the whole VPC.   |
| Single shared NAT (dev)                   | ~$32/month total                                                          | Dev availability target is best-effort; one NAT keeps cost down.            |
| VPC Flow Logs to CloudWatch (60s)         | CloudWatch ingestion + storage by retention                              | Forensics minute-by-minute is non-negotiable in regulated workloads.        |
| Public subnets exist at all               | Two extra subnets per AZ that mostly hold NAT GWs                        | Required to receive internet traffic at all. Keep them tiny (/24).          |

---

## Mülakatta Bu Soruyu Alırsan

Common interview probes about VPC design, in the order they tend to appear.

### Q1. "Why a `/16` and not a `/20` or `/24`?"

A `/16` gives 65,536 addresses, far more than we need today, but VPC CIDR blocks
are **fixed at creation** — you cannot expand them later (you can only attach
secondary CIDRs, which is messy). EKS pod density is the real budget killer
because the AWS VPC CNI consumes one private IP per pod by default. With a
`/20` (4,096 IPs), 100 nodes running 30 pods each is already 3,000 IPs, leaving
no room for ALBs, RDS, or future tiers. The `/16` makes future growth painless.
Per-subnet we use `/24` (256 IPs) which is generous for ALBs and NAT, and the
`/24` private-app subnets give us ~250 nodes per AZ.

### Q2. "Why one NAT Gateway per AZ and not just one for the whole VPC?"

Two reasons. **Availability**: a NAT Gateway is bound to a single AZ. If that
AZ has an outage, every private subnet in every other AZ loses internet egress
because their default route points there. With one NAT per AZ and per-AZ
private route tables, an AZ failure removes egress only for that AZ's pods.
**Cost** matters too in the other direction: traffic that crosses AZs to reach
the NAT gets charged data-transfer fees in addition to NAT data-processing fees.
Per-AZ NAT keeps the egress path AZ-local, eliminating that double charge.

In dev we toggle `single_nat_gateway = true` because the additional ~$32/month
× extra AZs isn't worth paying when the env target is best-effort.

### Q3. "Why VPC Flow Logs to CloudWatch instead of S3? Isn't S3 cheaper?"

Yes, S3 is cheaper at high volumes, but CloudWatch wins on **operability**:
queries via Insights are immediate, and we can wire metric filters → alarms
without a separate Athena setup. The trade is "pay for the index". For prod
we do the same thing the AWS reference architecture does: keep the most recent
year in CloudWatch for incident response, then ship to S3 with a CloudWatch
subscription for the long compliance tail. That move belongs in the
observability module, not here.

The 60-second aggregation interval (vs the maximum 600s) is a deliberate
choice: we trade slightly more cost for minute-level granularity that the
SOC actually needs to triage incidents.

### Q4. "What's the difference between an NACL and a Security Group? Which one are you using here?"

NACLs are stateless, subnet-scoped, allow + deny rules with explicit numbered
ordering. Security Groups are stateful, instance/ENI-scoped, allow-only rules
with no ordering. **In this module we ship only one SG** — the default SG,
stripped to empty as a defense-in-depth measure. We do not configure NACLs
because for our workloads NACLs add operational pain (return-traffic gotchas,
ephemeral port windows) without giving us anything that SGs and NetworkPolicy
don't already give us. NACLs become useful when you need broad, subnet-level
denies that bypass any individual SG mistake; we'd add them in the security
module if a specific threat model demands it.

### Q5. "Why is there no 0.0.0.0/0 route on the private-db subnets?"

Aurora and ElastiCache should never need to talk to the public internet. If
they did — say, to fetch an extension package — that would be a smell that
points at a config drift, not at a missing route. AWS APIs that the data tier
legitimately needs (KMS for storage encryption, Secrets Manager for rotation,
S3 for backups) reach the data tier via **VPC endpoints** (interface or
gateway), not via NAT. VPC endpoints are added in the security module, not
here, because they conceptually belong to the security posture, not the
network shape. Keeping the data tier "internet-dark" is a strong, easy-to-
audit control.

### Q6. "Why strip the default Security Group?"

CIS AWS Foundations 5.4 requires it. The default SG ships with a rule that
allows all traffic between resources that share it. If a developer accidentally
launches an EC2 instance and forgets to specify an SG, AWS attaches the
default SG. With the rule still in place, that instance silently joins the
mesh of everything else in the default SG. With the rule stripped to empty,
that same accident yields no implicit access — the instance is reachable only
by other things in the same (empty) SG, which is no things. It's a small,
free, defense-in-depth control.

### Q7. "How do EKS nodes know to use these subnets, and how does the AWS Load Balancer Controller place ALBs?"

Two tags do the work:

- `kubernetes.io/role/elb = 1` on **public** subnets tells the AWS LBC that
  internet-facing ALBs/NLBs can land here.
- `kubernetes.io/role/internal-elb = 1` on **private-app** subnets tells the
  LBC that internal ALBs/NLBs can land there.
- `kubernetes.io/cluster/<cluster-name> = shared` on every subnet tells EKS
  these are eligible to host worker nodes (also "owned" if the subnet is
  exclusive to one cluster).

Without these tags, the LBC silently fails to find a place for a Service of
type `LoadBalancer` with `aws-load-balancer-scheme: internet-facing`.

### Q8. "What happens if I delete the NAT Gateway by mistake?"

Three things, in order. **First**, EKS nodes lose outbound internet for any
public AWS endpoint they were using (image pulls from public ECR, package
installs). Pulls already cached on the node continue to work. **Second**,
ImagePullBackOff starts appearing on any deployment that needs a fresh image.
**Third**, in HA mode the impact is restricted to that AZ's pods because
each AZ's private route table points at the AZ-local NAT. Recovery is
`terraform apply` — the route table still references the old NAT GW ID
which is now gone, so Terraform sees drift and re-creates it (a few minutes).
The new NAT gets a new EIP, so any IP-based allowlists at downstream services
(rare, but exists for legacy partners) need an update — that's the argument
for keeping the EIP attached to a long-lived address pool, which is what we
do via `aws_eip` resources separated from the NAT GW.

### Q9. "Walk me through the IAM trust policy on the Flow Logs role. What attacks does it stop?"

The trust policy says: only the `vpc-flow-logs.amazonaws.com` service can
assume this role, **and only when** the request comes from our own
`aws:SourceAccount` and `aws:SourceArn` matches a flow-log resource in our
own region of our own account. The combination defeats the **confused deputy**
problem: another AWS customer can't accidentally (or maliciously) name our
role ARN in their own flow-log configuration and trick AWS into letting their
flow-log service write into our CloudWatch group. Both `SourceAccount` and
`SourceArn` are required because either alone has gaps — `SourceAccount`
allows any service-call from your own account; `SourceArn` alone could match
a service in a different account that you haven't pinned. Together they're
tight.

### Q10. "What would you change for prod?"

Four things.

1. `single_nat_gateway = false` — one NAT per AZ.
2. `flow_log_retention_days = 365` (or 731) — match the PCI-DSS audit window.
3. Pass `flow_log_kms_key_arn` from the security module so the log group is
   encrypted with our CMK rather than AWS-managed KMS.
4. Add VPC endpoints (S3, KMS, ECR, Secrets Manager, EKS) in the security
   module so the data tier and EKS nodes use them instead of NAT-routed
   traffic. That cuts NAT data-processing cost and removes a public path
   for AWS API calls.

The first two are flag flips at the env level. The last two are work in
adjacent modules. None of them require changing the VPC module itself — the
shape is right. That's what "good network plumbing" looks like.
