# `monitoring/grafana/dashboards/`

Grafana dashboards stored as JSON, auto-loaded into Grafana via the dashboard
sidecar pattern (each dashboard is mounted as a ConfigMap with the
`grafana_dashboard=1` label).

## Conventions

- Filename: `<scope>-<name>.json`, kebab-case.
  - `cluster-overview.json`, `istio-ambient-traffic.json`, `payments-api-slo.json`.
- Top of every dashboard:
  - **Description** field set with owner team and what to look at first during incidents.
  - **Tags** include the team, namespace, and severity (`runbook`).
  - **Variables** include `$env` (dev / prod) and `$namespace`.
- All panels reference recording rules (defined in `monitoring/prometheus/rules/`)
  rather than raw expressions where the same query is reused across panels.

## Planned dashboards

| Dashboard                          | What it answers                                                                         |
| ---------------------------------- | --------------------------------------------------------------------------------------- |
| `cluster-overview.json`            | Is the cluster healthy? Capacity, scheduling, control-plane health, etcd.               |
| `istio-ambient-traffic.json`       | Mesh traffic, mTLS coverage, ztunnel CPU, waypoint p99.                                  |
| `payments-api-slo.json`            | Payment success ratio, error budget burn-down, latency percentiles.                     |
| `biometric-pipeline.json`          | Iris+face match latency, queue depth, model version, false-reject rate.                  |
| `auth-service.json`                | Token issuance rate, JWT validation errors, auth failures by reason.                     |
| `aws-rds-aurora.json`              | Aurora CPU, replica lag, connections, slow-query rate.                                  |
| `aws-waf-edge.json`                | WAF blocks by rule, rate-limit triggers, bot category breakdown.                        |
| `cost-and-anomaly.json`            | NAT data processing, S3 request count, GuardDuty findings count over time.              |

## Dashboard provisioning

Grafana auto-discovers dashboards from any `ConfigMap` in any watched namespace
that carries the label `grafana_dashboard=1`. To add a new dashboard:

1. Drop the `.json` file in this directory.
2. CI builds a `ConfigMap` per file with the right label.
3. Argo CD applies it to the `observability` namespace.
4. Grafana picks it up within ~30 seconds.

No manual UI saves. Dashboards are code; UI changes that aren't reflected here
are wiped on the next sync.
