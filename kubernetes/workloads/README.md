# `kubernetes/workloads/`

Application workloads — Helm releases or Kustomize overlays describing which
container images run in which namespace with which configuration.

## Scope of this directory

This is **infrastructure-side** workload definition: which app runs where,
which ServiceAccount it uses, which ExternalSecret it pulls, which
HorizontalPodAutoscaler / PodDisruptionBudget protects it.

The **container image** itself is built and tagged by the application repo's
own pipeline. Image tags reach this repo via:

- **Argo CD Image Updater** (preferred) — automated promotion on new tags.
- **Manual PR bumping `image: tag`** — for environments under change-control freeze.

## Workload conventions

Every workload in this directory ships with:

| File / object                    | Purpose                                                                         |
| -------------------------------- | ------------------------------------------------------------------------------- |
| `Deployment`                     | Stateless apps. `replicas: >= 2`, podAntiAffinity across nodes/AZs.            |
| `ServiceAccount`                 | Annotated with the IRSA role ARN it can assume.                                 |
| `Service` (`ClusterIP`)          | Internal-only; ingress goes through the platform ALB / Istio waypoint.          |
| `HorizontalPodAutoscaler`        | CPU + custom metric (e.g., `payment_queue_depth`) where it makes sense.         |
| `PodDisruptionBudget`            | `minAvailable: 1` minimum, higher for multi-replica critical services.          |
| `NetworkPolicy`                  | Egress restricted to required services only — default-deny inherited from `policies/`. |
| `ExternalSecret`                 | Pulls secrets from Secrets Manager via ESO; **no plain `Secret` manifests**.    |
| `PrometheusRule` (in `monitoring/`) | Service-level latency / error / saturation alerts.                            |

## Initial workloads (placeholders until the app repos exist)

- `payments-api` — gRPC service in `payments` namespace.
- `biometric-matcher` — vector-matching engine in `biometrics`, isolated egress.
- `auth-service` — OIDC issuer + token service in `auth` namespace.
