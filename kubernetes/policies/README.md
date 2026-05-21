# `kubernetes/policies/`

Cluster-wide policy. Three kinds of guardrails live here:

1. **NetworkPolicy** — namespace-scoped default-deny + explicit allow rules.
2. **Pod Security** — Pod Security Admission profiles bound at namespace level.
3. **OPA Gatekeeper / Kyverno** — admission-time policies expressed in Rego or YAML.

## NetworkPolicy baseline

Each tenant namespace ships with **default-deny** for both ingress and egress:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: <ns>
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Specific allow rules are layered on top: e.g., `payments` may egress to
`biometrics:9000` and to AWS RDS endpoint resolution; nothing else.

## Pod Security

Namespaces are labeled to enforce a profile:

| Profile        | Where                                    | Bans                                                     |
| -------------- | ---------------------------------------- | -------------------------------------------------------- |
| `restricted`   | `payments`, `biometrics`, `auth`         | hostPath, hostNetwork, privileged, runAsNonRoot=false.   |
| `baseline`     | `observability`                          | hostNetwork, privileged.                                 |
| `privileged`   | `istio-system`, `platform-system`        | (none — these run system DaemonSets).                    |

## OPA / Kyverno policies

Examples of admission-time rules we plan to enforce:

| Rule                                              | Why                                                                |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| Image must come from approved ECR repo prefix.    | Stops random Docker Hub images from running with our IRSA scopes.  |
| Image tag must not be `:latest`.                  | Forces deterministic deploys — what was scanned is what runs.      |
| `ServiceAccount` must be set explicitly.          | Stops accidental use of `default` SA which has no IRSA annotation. |
| ResourceRequests must be set on every container.  | Required for HPA to function and for capacity planning.            |
| LoadBalancer Services not allowed in tenant ns.   | Tenants must go through the platform ALB and Istio gateway.        |

## Policy ordering

```
1. Pod Security        — runs first, blocks privileged escalation up front.
2. Kyverno / OPA        — content rules (image source, tag policy, required fields).
3. ResourceQuotas / LimitRanges — capacity guardrails.
4. NetworkPolicy       — runtime blast-radius limit (admission cannot enforce L3/L4 — CNI does).
```
