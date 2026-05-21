# `kubernetes/namespaces/`

Namespace declarations. Namespaces are the primary tenancy boundary in this
cluster — they carry the labels that drive Istio Ambient mode, PodSecurity
enforcement, and NetworkPolicy targeting.

## Namespaces (target)

| Namespace          | Purpose                                                                 | Mesh mode        | PodSecurity      |
| ------------------ | ----------------------------------------------------------------------- | ---------------- | ---------------- |
| `payments`         | Card and payment authorization services. PCI-DSS scope.                | Ambient (mTLS)   | restricted       |
| `biometrics`       | Iris / face matching pipeline; talks only to `payments` and KMS.        | Ambient (mTLS)   | restricted       |
| `auth`             | Customer + merchant identity services.                                  | Ambient (mTLS)   | restricted       |
| `platform-system`  | Cluster add-ons (External Secrets, AWS LBC, Karpenter if added).        | Off (privileged) | privileged-baseline |
| `observability`    | Prometheus, Grafana, Loki, Tempo, Alertmanager.                         | Ambient          | baseline         |
| `istio-system`     | Istio control plane (istiod, ztunnel daemonset).                        | (managed)        | privileged       |

## Required labels

Every namespace MUST carry:

```yaml
metadata:
  labels:
    istio.io/dataplane-mode: ambient        # opt into Istio Ambient mTLS
    pod-security.kubernetes.io/enforce: <profile>
    pod-security.kubernetes.io/enforce-version: latest
    payeye.io/data-classification: <public|internal|confidential|pci>
    payeye.io/owner: <team-name>
```

## Why ambient mode

Istio Ambient (ztunnel + waypoint) gives us mTLS and L4 authz **without sidecars**:

- No init-container delay → faster pod start, simpler PID-1 semantics.
- No per-pod Envoy → much lower memory, predictable noisy-neighbor behavior.
- Mesh upgrades happen at the ztunnel/waypoint layer, not by re-rolling every pod.

L7 features (header-based routing, RBAC) are opt-in by attaching a waypoint proxy
to namespaces that need them — `payments` and `auth` will, others will not.
