# `monitoring/`

Observability assets that live **alongside** but logically separate from
infrastructure code. Splitting them out means a Grafana dashboard tweak
does not need to go through the same change-control as a VPC change.

## Subdirectories

| Subdirectory             | Purpose                                                                                  |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| `prometheus/rules/`      | PrometheusRule CRs — recording rules and alert rules (latency SLO, error budget, infra). |
| `grafana/dashboards/`    | JSON dashboards loaded via Grafana sidecar (`grafana_dashboard=1` ConfigMap label).      |

## Three-pillar coverage

| Pillar  | Tool                            | What we capture                                                            |
| ------- | ------------------------------- | -------------------------------------------------------------------------- |
| Metrics | Prometheus + AWS CloudWatch     | Cluster, node, pod, app metrics; AWS service metrics via CloudWatch agent. |
| Logs    | Loki + AWS CloudWatch Logs      | App stdout via Loki; AWS service logs (VPC FL, ALB, WAF) in CloudWatch.    |
| Traces  | OpenTelemetry → Tempo / X-Ray   | Distributed traces from Istio ambient + app SDK; correlated via TraceID.   |

## Alerting

Alerts route through Alertmanager → SNS → PagerDuty (placeholder), with
**severity-based routing**:

- `severity=critical` → page on-call immediately, runbook link required.
- `severity=warning`  → email + Slack, no page.
- `severity=info`     → Slack only.

## Where dashboards come from

- **Open-source baseline** — Kubernetes mixin, Istio Ambient dashboards, Node Exporter Full.
- **Custom** — biometric-pipeline latency, payment authorization rates, KMS key usage trends.
