# `kubernetes/observability/`

> Cluster-side observability stack: Prometheus + Alertmanager (operator) +
> Grafana + Loki + Promtail. Installed via Helm with lean values tuned for
> a 2× t3.medium dev cluster, scaled up via the same values file for prod.

---

## What this directory installs

| Component                | Helm chart                              | Purpose                                                              |
| ------------------------ | --------------------------------------- | -------------------------------------------------------------------- |
| Prometheus Operator      | `kube-prometheus-stack`                 | CRD-based Prometheus + Alertmanager + ServiceMonitor management.    |
| Prometheus               | `kube-prometheus-stack`                 | Cluster + workload metrics scraper. 1d retention in dev, 30d+ prod. |
| node-exporter (DaemonSet)| `kube-prometheus-stack`                 | Per-node OS-level metrics (CPU, memory, disk, net).                  |
| kube-state-metrics       | `kube-prometheus-stack`                 | Kubernetes object state metrics (pod count, condition, restarts).   |
| Grafana                  | `kube-prometheus-stack`                 | Dashboards UI. Wired to Prometheus + Alertmanager datasources.       |
| Alertmanager             | `kube-prometheus-stack` (disabled in dev)| Alert routing → SNS/PagerDuty in prod.                              |
| Loki (single binary)     | `loki-stack`                            | Log aggregation. Filesystem-backed in dev; S3 in prod.              |
| Promtail (DaemonSet)     | `loki-stack`                            | Per-node log shipper, ships container stdout/stderr to Loki.        |

Scrape targets default (kube-prometheus-stack defaults):

- API server, kubelet, kube-proxy, CoreDNS, kube-state-metrics, node-exporter,
  Prometheus self, Grafana self, the operator. **19 active targets** on a
  freshly installed dev cluster.

## Files

```
kubernetes/observability/
├── install.sh                            # Idempotent helm install for both releases
├── values-kube-prometheus-stack.yaml     # Lean chart values (dev sizing)
└── README.md                             # ← you are here
```

## Install

After the EKS cluster + dev composition apply succeeds:

```bash
# 1. Update kubeconfig
$(terraform -chdir=../../terraform/environments/dev output -raw eks_kubeconfig_command)

# 2. Run the script
./install.sh
```

Idempotent — re-running upgrades to the latest chart version per `helm upgrade --install`.

## Access (dev)

```bash
# Grafana — admin / payeye-demo
kubectl -n observability port-forward svc/kps-grafana 3000:80
open http://localhost:3000

# Prometheus
kubectl -n observability port-forward svc/kps-prometheus 9090:9090
open http://localhost:9090
```

For prod, expose via ALB Ingress with TLS through the dns-tls module + AWS WAF
in front, NOT directly via port-forward.

## What changes for prod

The same `install.sh` works in prod, but `values-kube-prometheus-stack.yaml`
must be replaced with prod-grade values. The relevant deltas:

| Setting                              | dev                       | prod                                                          |
| ------------------------------------ | ------------------------- | ------------------------------------------------------------- |
| `alertmanager.enabled`               | `false`                   | `true`, with SNS receiver pointed at PagerDuty/Slack.         |
| `prometheus.prometheusSpec.retention`| `1d`                      | `30d` minimum (or 90d for some PCI-DSS readings).             |
| `prometheus.prometheusSpec.replicas` | `1`                       | `2` for HA + Thanos sidecar for long-term S3 storage.         |
| Storage class                        | `gp2`                     | `gp3-encrypted` (KMS-encrypted via the security module's CMK).|
| Storage size (Prometheus)            | `5Gi`                     | `200Gi+` depending on retention.                              |
| Loki backend                         | filesystem (single PV)    | S3 (with KMS encryption) for chunks + DynamoDB for index.     |
| Loki replicas                        | 1 (single binary)         | 3+ (simple-scalable mode with reader/writer split).           |
| Grafana persistence                  | `false`                   | `true` (10Gi gp3) so dashboards survive pod restarts.         |
| Grafana ingress                      | port-forward only         | ALB Ingress with TLS via ACM + WAF in front.                  |
| Grafana auth                         | local admin password      | OIDC (Okta/Auth0/Cognito) via the `auth.generic_oauth` block. |

## What is NOT here yet

- **PrometheusRule CRs** — alerting + recording rules. Live in `monitoring/prometheus/rules/`
  in the repo and are applied separately (dev-only path: `kubectl apply -f ...`;
  prod path: through GitOps/Argo CD).
- **Custom Grafana dashboards** — JSON in `monitoring/grafana/dashboards/`, mounted
  as ConfigMaps with the `grafana_dashboard=1` label that the Grafana sidecar picks up.
- **Tempo / X-Ray / OpenTelemetry collector** — distributed tracing. Plan for the
  next observability iteration.
- **Container Insights** — AWS-native EKS observability. Optional addition for
  AWS-side dashboards (e.g., automatic per-pod CPU/memory in CloudWatch).
