# `kubernetes/istio/`

Istio Ambient mesh installation and policy. The mesh provides:

- **Automatic mTLS** between pods (via ztunnel) — encrypted east-west traffic by default.
- **L4 authorization policies** (who can talk to whom on which port).
- **L7 features** (HTTP routing, header-based RBAC, JWT validation) on opt-in via **waypoint proxies**.

## Components installed

| Component   | Where                          | Role                                                                                |
| ----------- | ------------------------------ | ----------------------------------------------------------------------------------- |
| `istiod`    | `istio-system` namespace       | Control plane: pushes config to ztunnel and waypoints.                              |
| `ztunnel`   | DaemonSet on every node         | Per-node L4 proxy; intercepts pod traffic, terminates and originates mTLS.          |
| Waypoint(s) | Deployment in target namespace | Optional per-namespace L7 proxy when AuthorizationPolicy needs HTTP-level matching. |

## Trust domain

```
spiffe://payeye.local/ns/<namespace>/sa/<serviceaccount>
```

Service identities are bound to Kubernetes ServiceAccounts. AuthorizationPolicy
expresses access in those SPIFFE terms — not by IP or pod name.

## Layered access control

```
1. NetworkPolicy   (cluster-native, L3/L4)  — broad allow/deny by namespace + port.
2. Istio L4 AuthZ  (ztunnel)                — service-account → service-account allowlist.
3. Istio L7 AuthZ  (waypoint)               — methods, paths, JWT claims (only where needed).
```

A pod must clear **all three layers** to reach another pod. Defense in depth.

## What lives in this directory

- `install/`         — Istio Helm values + ambient profile.
- `waypoints/`       — Waypoint deployments per namespace (`payments`, `auth`).
- `authz-policies/`  — `AuthorizationPolicy` resources, namespace-scoped.
- `peer-authentication/` — `PeerAuthentication` set to **STRICT** mTLS at mesh root.
