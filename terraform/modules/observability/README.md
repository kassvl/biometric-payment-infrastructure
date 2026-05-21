# `terraform/modules/observability/`

> The AWS-side of observability — log groups, metrics, dashboards, alarms,
> and notification topics. The in-cluster side (Prometheus rules,
> Grafana dashboards) lives in `monitoring/` at the repo root.

## What this module creates

| Resource                         | Detail                                                                                          |
| -------------------------------- | ----------------------------------------------------------------------------------------------- |
| CloudWatch log groups            | `/payeye/<env>/eks/cluster`, `/payeye/<env>/vpc/flowlogs`, `/payeye/<env>/waf`, etc. KMS-encrypted, retention per env policy. |
| CloudWatch metric filters        | Extract custom metrics from logs (4xx rate, auth failures, slow DB queries).                    |
| CloudWatch dashboards            | Per-environment: cluster health, RDS performance, WAF blocks, GuardDuty findings.               |
| CloudWatch alarms                | Tied to the dashboards; route to SNS for paging / Slack / email.                                |
| SNS topics                       | `payeye-<env>-page` (critical), `payeye-<env>-notify` (warning/info), with KMS encryption.      |
| EventBridge rules (optional)     | Fan-out: GuardDuty Finding → SecurityHub + SNS + Lambda triage stub.                            |
| S3 bucket — long-term log archive | Logs older than CloudWatch retention land here in Glacier IR for the 7-year FinTech audit window. |

## Retention by environment

| Log group                       | dev    | prod    | Why prod is longer                                        |
| ------------------------------- | ------ | ------- | --------------------------------------------------------- |
| EKS control plane               | 7 d    | 90 d    | Operational debugging.                                     |
| VPC Flow Logs                   | 30 d   | 365 d   | Network forensics window required by PCI-DSS / DORA.       |
| WAF logs                        | 30 d   | 365 d   | Attack pattern review across long horizons.                |
| CloudTrail                      | 90 d   | **7 y** | Regulatory; archived to S3 with object-lock after 90 days. |
| Application logs (via Loki / CW)| 7 d    | 30–90 d | Cost vs SRE need balance; long-term goes to S3.            |

The **"Mülakatta Bu Soruyu Alırsan"** Q&A (CloudWatch vs Loki vs OpenSearch,
why S3 archive vs CloudWatch long retention, EventBridge for fan-out,
alarm → page vs alarm → ticket) is in the upcoming `infra(observability):` commit.
