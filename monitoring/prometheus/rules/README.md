# `monitoring/prometheus/rules/`

Prometheus **recording rules** and **alerting rules** as `PrometheusRule`
custom resources. Loaded by the Prometheus operator that ships with the
`kube-prometheus-stack` Helm release in the `observability` namespace.

## Two rule kinds

| Kind          | Purpose                                                                      |
| ------------- | ---------------------------------------------------------------------------- |
| **Recording** | Pre-compute expensive or repeated queries (e.g., 5m error rate by service).  |
| **Alerting**  | Fire when a recorded value crosses a threshold for a sustained window.        |

## Required labels on every alert

```yaml
labels:
  severity: critical | warning | info
  team: platform | payments | biometrics | security
  runbook: https://github.com/.../docs/runbooks/<name>.md
```

Alertmanager routes on `severity` and `team`. Pages always include the
`runbook` annotation so the on-call engineer has a procedure to follow.

## Alert categories planned

| Category         | Examples                                                                                  |
| ---------------- | ----------------------------------------------------------------------------------------- |
| SLO burn         | Payment-API success ratio < 99.9% over 1h / 6h / 24h windows (multi-window multi-burn).   |
| Latency          | p99 of `payments-api` > 300ms for 10 minutes.                                              |
| Saturation       | Aurora CPU > 80% for 15 min; node `kubelet_running_pods` > capacity threshold.            |
| Error            | 5xx rate from waypoint > 1% for 5 minutes.                                                 |
| Security         | GuardDuty `Severity=HIGH` finding → immediate page (via SNS → CloudWatch → Alertmanager). |
| Infra            | RDS replica lag, EBS volume near-full, certificate expiry < 30 days.                       |
| Cost             | NAT Gateway data processing > anomaly threshold (potential data exfil or runaway loop).    |

## What does NOT go here

- AWS-native alarms (CloudWatch alarms on RDS, ALB) live in `terraform/modules/observability/`.
  Those fire on AWS metrics that Prometheus can't see.
- Synthetic / blackbox checks (external uptime probes) live with the synthetic-monitor manifests.
