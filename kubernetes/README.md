# `kubernetes/`

Kubernetes-side configuration that runs **on top of** the AWS infrastructure
created by `terraform/`. The cluster itself (control plane, node groups, IRSA
OIDC provider, core add-ons) is provisioned by the `eks/` Terraform module.
Anything *inside* the cluster lives here.

## Why a separate directory from `terraform/`

- **Different lifecycle.** Cluster shape rarely changes; in-cluster workloads change daily.
- **Different tooling.** Kustomize / Helm / Argo CD are first-class for in-cluster state.
- **Different review cadence.** App engineers can ship YAML changes without touching IAM or VPC.

## Subdirectories

| Subdirectory        | Purpose                                                                                            |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| `namespaces/`       | Namespace declarations with labels for Istio Ambient mode, PodSecurity, and ResourceQuotas.        |
| `istio/`            | Istio Ambient mesh installation (control plane + ztunnel DaemonSet + waypoint proxies, AuthZ).     |
| `workloads/`        | Application deployments (placeholder Helm releases / kustomizations for biometric services).      |
| `external-secrets/` | External Secrets Operator + ClusterSecretStore wired to AWS Secrets Manager via IRSA.              |
| `policies/`         | OPA/Gatekeeper or Kyverno policies, Kubernetes NetworkPolicies, PodSecurity profile mappings.      |

## Application order (cold-start)

```
1. namespaces/         (must exist before any policy can target them)
2. policies/           (Pod Security & NetworkPolicies enforced before workloads land)
3. istio/              (mesh data plane up before app traffic flows)
4. external-secrets/   (ESO ready before workloads referencing ExternalSecret resources)
5. workloads/          (last; everything they need is already in place)
```
