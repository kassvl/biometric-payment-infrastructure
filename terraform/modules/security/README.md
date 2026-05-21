# `terraform/modules/security/`

> Account-wide security posture. Everything here is "defense in depth" —
> controls that fire even if a developer makes a mistake elsewhere.

## What this module creates

| Resource                   | Detail                                                                                              |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| AWS GuardDuty (detector)   | Threat detection on VPC Flow Logs, CloudTrail, S3, EKS audit logs, Malware Protection on EBS.       |
| AWS Security Hub           | Aggregator for GuardDuty + Inspector + Macie + Config rules; **CIS AWS Foundations 1.4** standard on. |
| AWS Config                 | Continuous configuration recording with managed and custom rules; logs to a dedicated S3 bucket.    |
| AWS WAF v2 (regional)      | Attached to the ALB; AWS Managed Rules + custom rate-limit + geographic rules.                      |
| KMS CMKs                   | Account-wide keys: `payeye-logs`, `payeye-secrets`, `payeye-rds`. Each with key policy + rotation.  |
| IAM password policy        | 14-char min, complexity, no reuse for 24, 90-day rotation.                                          |
| Default-region SCP friendly | Module is written so it composes cleanly with an Org-level SCP that pins region to eu-central-1.   |
| CloudTrail                  | Multi-region trail, log file validation on, immutable storage in dedicated S3 with object lock.    |

## Why these controls exist

| Control            | What it stops                                                                                       |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| GuardDuty          | Compromised IAM creds (impossible-travel calls), crypto-mining EC2 instances, data exfil patterns.  |
| Security Hub + CIS | Configuration drift away from baseline (public S3, root MFA off, unused keys).                      |
| WAF                | OWASP Top 10 at the edge; rate-limits brute-force on auth endpoints.                                |
| KMS rotation       | Limits the window of value if a key is ever leaked; required for PCI-DSS encryption requirements.   |
| CloudTrail + lock  | Tamper-evident audit log — even an admin cannot rewrite history.                                    |

The **"Mülakatta Bu Soruyu Alırsan"** Q&A (defense-in-depth, blast radius,
SCP vs IAM policy, CIS gaps that need custom rules, GuardDuty findings
triage flow) is in the upcoming `infra(security):` commit.
