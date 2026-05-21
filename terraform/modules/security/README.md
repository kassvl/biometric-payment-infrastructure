# `terraform/modules/security/`

> Account-wide and per-VPC security posture. Everything here is "defense in
> depth" — controls that fire even when a developer makes a mistake elsewhere.
> This module is the foundation that EKS, RDS, and the application tier
> assume is in place.

---

## Scope of this commit

This module currently ships the **baseline** controls every downstream module
depends on:

| Control                        | What it gives                                                                          |
| ------------------------------ | -------------------------------------------------------------------------------------- |
| **Multi-CMK KMS**              | One CMK per domain (`logs`, `secrets`, `rds`, `ebs`) with rotation and per-service policy. |
| **VPC Endpoints**              | Gateway endpoints (S3, DynamoDB) + interface endpoints (10 services) — keeps AWS API traffic on the AWS backbone. |
| **WAF v2 (Regional)**          | Managed rule sets + per-IP rate limit, CloudWatch logging, ready to attach to ALB.    |
| **IAM password policy**        | Account-wide; PCI-DSS-aligned length, complexity, max-age, reuse prevention.           |
| **EBS default encryption**     | Account+region default; new EBS volumes are encrypted with our `ebs` CMK by default.   |

The **threat-detection layer** (GuardDuty, Security Hub, AWS Config,
CloudTrail with object-lock S3) is intentionally **deferred to a follow-up
commit** in this same module so this PR stays reviewable and the resources
that don't depend on threat detection (EKS, RDS) can land first.

---

## What this module creates

### KMS (multi-CMK)

| Domain   | Purpose                                                                  | Service grants                                |
| -------- | ------------------------------------------------------------------------ | --------------------------------------------- |
| `logs`   | CloudWatch log group encryption (VPC FL, EKS audit, WAF, app logs).     | `logs.<region>.amazonaws.com`                 |
| `secrets`| Secrets Manager (RDS master pw, OIDC client secrets, app credentials).  | `secretsmanager.amazonaws.com`                |
| `rds`    | Aurora storage encryption + Performance Insights.                        | `rds.amazonaws.com`                           |
| `ebs`    | EKS node EBS volumes; account-region default encryption key.             | `ec2.<region>.amazonaws.com`                  |

Every CMK has:
- Annual rotation enabled (`enable_key_rotation = true`).
- Account-root admin statement (recovery path if the policy bricks itself).
- Service-principal grant scoped by `aws:SourceAccount` (confused-deputy guard).
- Alias `alias/<project>-<env>-<domain>` for human-friendly references.

### VPC Endpoints

- **Gateway**: `s3`, `dynamodb` — attached to private-app + private-db route tables. Free, route-table-based, no ENIs.
- **Interface** (default 10): `kms`, `secretsmanager`, `ecr.api`, `ecr.dkr`, `eks`, `sts`, `ec2`, `logs`, `ssm`, `monitoring` — one ENI per AZ in private-app subnets, private DNS enabled.
- A purpose-built SG `<project>-<env>-vpc-endpoints` allows 443 ingress from the VPC CIDR only.

### WAF v2 — Regional WebACL

| Priority | Rule                                                | Action       |
| -------- | --------------------------------------------------- | ------------ |
| 1        | `AWSManagedRulesAmazonIpReputationList`             | Managed      |
| 2        | `AWSManagedRulesAnonymousIpList`                    | Managed      |
| 10       | `AWSManagedRulesCommonRuleSet` (OWASP Top-10)       | Managed      |
| 11       | `AWSManagedRulesKnownBadInputsRuleSet`              | Managed      |
| 12       | `AWSManagedRulesSQLiRuleSet`                        | Managed      |
| 100      | `RateLimitPerSourceIp` (configurable per env)       | **Block**    |

Logs go to a CloudWatch log group named `aws-waf-logs-<project>-<env>` (the
`aws-waf-logs-` prefix is required by AWS). `authorization` and `cookie`
headers are redacted from the log stream.

### IAM password policy (account-wide)

`min_length=14`, all character classes required, max age 90 days, reuse
prevention 24, change-password permission for users.

### EBS default encryption

`aws_ebs_encryption_by_default = true` plus `aws_ebs_default_kms_key`
pointing at the `ebs` CMK.

## File layout

```
terraform/modules/security/
├── versions.tf                 # Pinned terraform + aws provider, no provider/backend block
├── variables.tf                # 200+ lines of typed inputs with validation
├── data.tf                     # caller_identity, partition, region
├── locals.tf                   # KMS catalog, common_tags, cross-variable validation
├── kms.tf                      # for_each over kms_keys_selected; per-key policies
├── vpc-endpoints.tf            # SG + gateway endpoints + interface endpoints
├── waf.tf                      # CloudWatch log group + WebACL + logging configuration
├── iam.tf                      # Account password policy
├── ebs.tf                      # Default encryption + default KMS key
├── outputs.tf                  # KMS maps, VPC endpoint maps, WAF ARN, SG
├── terraform.example.tfvars    # Committed example
└── README.md                   # ← you are here
```

---

## Usage

Consumed by an environment composition after the VPC module:

```hcl
module "vpc" {
  source = "../../modules/vpc"
  # ...
}

module "security" {
  source = "../../modules/security"

  project_name = "biopay"
  env          = "dev"

  # VPC wiring (only required when enable_vpc_endpoints = true)
  vpc_id                       = module.vpc.vpc_id
  vpc_cidr_block               = module.vpc.vpc_cidr_block
  private_app_subnet_ids       = module.vpc.private_app_subnet_ids
  private_app_route_table_ids  = module.vpc.private_app_route_table_ids
  private_db_route_table_ids   = module.vpc.private_db_route_table_ids

  # Account-wide singletons (keep true in ONE env per account)
  enable_iam_password_policy    = true
  enable_default_ebs_encryption = true

  extra_tags = {
    OnCallTeam = "platform"
  }
}
```

After apply, downstream modules consume the outputs:

```hcl
module "rds" {
  source = "../../modules/rds"

  storage_kms_key_arn = module.security.kms_key_arns["rds"]
  # ...
}

module "eks" {
  source = "../../modules/eks"

  ebs_kms_key_arn  = module.security.kms_key_arns["ebs"]
  logs_kms_key_arn = module.security.kms_key_arns["logs"]
  # ...
}
```

---

## Account-singleton resources — read this before composing

Three resources in this module are **AWS account (or account+region)
singletons**. There is exactly one of each per account/region; multiple
Terraform stacks trying to manage them will conflict on the second `apply`.

| Resource                          | Singleton scope        | Variable                          |
| --------------------------------- | ---------------------- | --------------------------------- |
| `aws_iam_account_password_policy` | Per AWS account        | `enable_iam_password_policy`      |
| `aws_ebs_encryption_by_default`   | Per AWS account+region | `enable_default_ebs_encryption`   |
| `aws_ebs_default_kms_key`         | Per AWS account+region | `enable_default_ebs_encryption`   |

**Rule of thumb:** in a multi-environment account, set these flags to `true`
in **only one** environment composition (typically `prod/`, or a dedicated
`account-baseline/`). In the others, set them to `false`. The CMKs and VPC
endpoints are not singletons and are safe to create per-environment.

---

## Mülakatta Bu Soruyu Alırsan

A 10-question drill on the controls above.

### Q1. "Why one CMK per domain — `logs`, `secrets`, `rds`, `ebs` — and not just one shared CMK?"

Three reasons. **Blast-radius isolation**: revoking a key permission on the
`secrets` CMK does not break the `logs` CMK or the `rds` CMK. **Audit
fidelity**: CloudTrail records every cryptographic operation against a key
ARN, so "who decrypted RDS storage at 03:14" is a single key-ARN filter
instead of a haystack across all encryption use. **Forensic key revocation**:
if an IRSA role is suspected of misuse, we can scope the response to just
the keys it should have touched, not disable encryption everywhere. The
trade-off is roughly $1/month per CMK plus minor per-operation costs.
For a payment-grade workload, that is rounding error.

### Q2. "Why both gateway and interface VPC endpoints? Aren't they the same thing?"

They are very different. **Gateway endpoints** (only S3 and DynamoDB) attach
to **route tables**, take no IPs, have no ENIs, and are free. They redirect
in-region traffic to those services onto the AWS backbone. **Interface
endpoints** create one **ENI per subnet per service** with a private DNS
entry, are charged per-ENI-per-AZ-hour and per-GB processed, and work for
~120 AWS services (KMS, Secrets Manager, ECR, EKS, etc.). Together they
remove the need to route AWS API calls through a NAT Gateway: the data tier
reaches S3/DynamoDB via gateway endpoints, the app tier reaches KMS/Secrets
Manager/ECR via interface endpoints, and only public-internet egress hits
the NAT.

### Q3. "How does the `aws:SourceAccount` condition on the KMS key policy stop a confused-deputy attack?"

Without it, a Service principal grant says "this AWS service may use this
key". An attacker in another AWS account can sometimes invoke that service
**naming our key** in a way that makes the service call our key on the
attacker's behalf — that's the "confused deputy". With
`Condition.StringEquals.aws:SourceAccount = <our account ID>`, the service
is only allowed to use our key when the original API call originated in our
own account. The deputy can no longer be confused: a cross-account caller
fails the condition. We pair it with `aws:SourceArn` whenever the service
exposes a SourceArn (e.g., on log delivery).

### Q4. "Walk me through the WAF rule order — why is rate-limit at priority 100, IP reputation at 1?"

Rules execute in priority order, lowest first. **Cheap drops go first**.
`AmazonIpReputationList` and `AnonymousIpList` are simple IP set lookups —
pennies of CPU per request, dropping known-bad sources before we spend any
cycles on body parsing. **Signature scans run next** (priority 10–12):
CommonRuleSet, KnownBadInputs, SQLi — these inspect request bodies and
headers, more expensive but high-value. **Rate limit runs last** (priority
100) because it must observe the request to count it. Putting rate limit
at priority 1 would still work but would require WAF to count even malicious
traffic from already-banned IPs, wasting capacity.

### Q5. "What's the difference between `override_action.none {}` and `action { block }` on a managed rule group?"

For **managed rule groups**, you can't change the action of individual rules
inside the group (those are AWS's responsibility). `override_action` controls
whether the group's rules behave as their authors intended (`none {}` = run
the rules' configured actions, typically Block) or are forced to count-only
(`count {}` = match but don't block, used when tuning a new rule group
before you trust it). For **custom rules** like our rate limit, you set
`action` directly because there is no upstream author — you own the rule
and its action.

### Q6. "Why is the rate-limit set per source IP and not per HTTP path or per JWT subject?"

WAF's `rate_based_statement` aggregates by **a single key**: source IP,
forwarded-IP, header value, query argument, or HTTP method. Per-source-IP
is the cheapest and most universal — works for unauthenticated endpoints
(login, registration) where there is no JWT yet. Per-JWT-subject would need
a `forwarded_ip` or header-based aggregation key, which we'd add as an
**additional** rule on the auth endpoints once we have one. The current
rule is the floor; the application service mesh adds finer per-subject
limits at the L7 layer (Istio waypoint) where the JWT has been validated.

### Q7. "Why is `enable_iam_password_policy` flagged off in dev and on in prod?"

Because there is exactly **one IAM account password policy per AWS account**.
If both `dev/` and `prod/` Terraform compositions try to manage it, the
second `apply` clobbers the first; if they configure it differently, every
apply flips back and forth — drift hell. The pattern is to elect **one
environment per account** as the owner of the singleton. In a real
multi-account org, this lives in an `account-baseline/` Terraform stack
that runs in the management account, and individual workload accounts
inherit via SCPs.

### Q8. "What happens if I revoke the `ebs` CMK by accident?"

Several things in sequence. **Existing volumes** keep working until they're
detached and re-attached — they hold a grant against the key from when they
were created. **New volume creation** fails immediately with
`KMSAccessDeniedException`. **Snapshots** of existing volumes also fail.
Recovery: restore the key (if within the deletion window), or update
`aws_ebs_default_kms_key` to point at a different CMK. The 30-day deletion
window on every CMK in this module is the panic-button buffer.

### Q9. "Why redact `authorization` and `cookie` headers in the WAF logs?"

Bearer tokens and session cookies in WAF logs are exfil targets. WAF logs
land in CloudWatch and may be exported to S3 for long retention; if a
read-only IAM user with `logs:GetLogEvents` is ever compromised, those
tokens become login-as-user material. Redaction does not disable WAF's
ability to **match** on those headers (the rules still see the cleartext
during evaluation) — it only blanks them in the log stream. The downside
is operational: when triaging a real attack you can't see "what cookie did
the attacker present", but the SIEM has its own correlation paths for that.

### Q10. "What's missing from this module that you'd add for prod?"

Five things, in priority order.

1. **GuardDuty + Security Hub + AWS Config**: account-level threat
   detection, CSPM, and config-rules. Deferred to the next commit so
   this PR stays small and focused.
2. **CloudTrail with S3 Object Lock (Compliance mode)**: tamper-evident
   audit log. Belongs in this module conceptually; deferred for the same
   reason.
3. **AWS Network Firewall** in front of egress, for L7 inspection of
   private-subnet outbound traffic to non-AWS destinations. Adds
   meaningful cost; needed for some PCI-DSS readings.
4. **AWS Inspector** for continuous EC2/EKS image vulnerability scanning
   — natural fit with the Trivy CI gate.
5. **Service Control Policies** at the AWS Organizations level: pin
   region, deny root-user actions, deny disabling logging. SCPs live
   above account boundaries and are the correct layer for the
   "always-on" guarantees IAM permissions cannot give you.
