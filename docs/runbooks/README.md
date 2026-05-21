# `docs/runbooks/`

Operational runbooks. Each file is the procedure an on-call engineer follows
when a specific alert fires or a specific incident type is declared.

## Required structure

Every runbook MUST start with:

```markdown
# Runbook: <Title>

**Trigger:** <which alert or condition opens this runbook>
**Severity:** <critical | warning>
**Owner team:** <team>
**Last reviewed:** <YYYY-MM-DD by Name>

## TL;DR
<one sentence: the most important action to take RIGHT NOW>

## Verify the alert is real
<1-3 quick commands or dashboards to confirm it's not a false positive>

## Mitigation steps
1. <step>
2. <step>
3. <step>

## Post-incident
- File an incident review issue.
- Update this runbook if anything was unclear or wrong.
```

## Planned runbooks

| File                                  | Triggered by                                                               |
| ------------------------------------- | -------------------------------------------------------------------------- |
| `aurora-failover.md`                  | Aurora writer instance unhealthy / availability alert.                     |
| `eks-node-not-ready.md`               | One or more nodes in `NotReady` for > 5 min.                                |
| `acm-cert-expiring.md`                | ACM cert expiry alarm < 30 days (should never happen — auto-renew).         |
| `guardduty-high-finding.md`           | GuardDuty `Severity=HIGH` finding (impossible-travel, malicious IP, etc.). |
| `vpc-nat-data-processing-anomaly.md`  | NAT egress bytes anomaly (potential exfil or runaway loop).                |
| `eks-control-plane-upgrade.md`        | Quarterly EKS minor-version upgrade.                                        |
| `secrets-manager-rotation-failure.md` | A scheduled secret rotation failed.                                         |
| `disaster-recovery-failover.md`       | Primary region (`eu-central-1`) declared unhealthy; promote `eu-west-1`.    |

## Quality bar

- A runbook that doesn't include exact commands and exact dashboard URLs is **not done**.
- A runbook that hasn't been reviewed in the last 6 months gets a `stale` label and a follow-up issue.
- Every page-level alert MUST link to a runbook. No runbook → no page rule.
