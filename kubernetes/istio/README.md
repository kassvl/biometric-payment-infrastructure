# `kubernetes/istio/`

> Istio **Ambient mesh** installation and policy. **No sidecars.** Traffic is
> intercepted by an `istio-cni` DaemonSet and tunneled through a `ztunnel`
> DaemonSet that terminates and originates mTLS for every pod in any namespace
> labeled `istio.io/dataplane-mode=ambient`. L7 features (HTTP routing,
> JWT-aware AuthorizationPolicy) are added selectively via **Waypoint Proxies**
> created with the Kubernetes Gateway API.

---

## Why Ambient (and not classic sidecar)

| Concern                    | Classic sidecar                          | Ambient (ztunnel + waypoint)                    |
| -------------------------- | ---------------------------------------- | ----------------------------------------------- |
| Memory per pod             | +50–200 MiB Envoy sidecar                | 0 (proxy is per-node, not per-pod)              |
| Pod startup                | Init container delay, race conditions    | Instant — no proxy in the pod                   |
| L7 cost when not needed    | Always paid (sidecar runs even for L4)   | Opt-in via waypoint, pay only where used        |
| Mesh upgrade impact        | Re-roll every workload pod               | Update ztunnel DaemonSet once                   |
| App + sidecar lifecycle    | Tightly coupled                          | Decoupled — apps know nothing about the mesh    |
| Maturity                   | Years in production                      | GA in Istio 1.22+, broadly adopted by 2026      |

The portfolio narrative ("modern FinTech infrastructure on AWS") matches
ambient: it is the architecture an org would pick for a 2026 greenfield
EKS cluster.

---

## Components installed

| Component        | Where                          | Role                                                                               |
| ---------------- | ------------------------------ | ---------------------------------------------------------------------------------- |
| `istiod`         | `istio-system` (Deployment)    | Control plane. Pushes config to ztunnel and to every waypoint.                     |
| `istio-cni`      | `istio-system` (DaemonSet)     | Runs on every node. Programs node-level iptables to redirect ambient-pod traffic. |
| `ztunnel`        | `istio-system` (DaemonSet)     | Per-node L4 proxy. Terminates and originates mTLS for every ambient pod.          |
| Waypoint proxy   | Tenant namespace (Deployment)  | Optional. L7 inspection (HTTP routing, AuthorizationPolicy with method/path/JWT). |

## Trust model

Identities are SPIFFE IDs derived from each pod's Kubernetes ServiceAccount:

```
spiffe://biopay.local/ns/<namespace>/sa/<serviceaccount>
```

`AuthorizationPolicy` uses these identities, not IPs or pod names. The
policy survives pod restarts, deployment replacements, and IP churn —
identity is bound to the SA, not to ephemeral metadata.

## Files

```
kubernetes/istio/
├── install-ambient.sh                          # Idempotent installer (helm-based)
├── namespaces.yaml                              # Opt-in label for default namespace
├── peer-authentication-strict.yaml              # Mesh-wide STRICT mTLS
├── waypoints/
│   └── default-namespace-waypoint.yaml          # Gateway API waypoint for L7 features
├── authz-policies/
│   └── productpage-l7.yaml                      # L7 ALLOW rule applied at the waypoint
└── README.md                                    # ← you are here
```

## Install

After the EKS cluster + dev composition apply finishes:

```bash
# 1. Update kubeconfig
$(terraform -chdir=../../terraform/environments/dev output -raw eks_kubeconfig_command)

# 2. Install ambient mesh + Gateway API CRDs + STRICT mTLS
./install-ambient.sh

# 3. Opt the default namespace into ambient mode
kubectl apply -f namespaces.yaml

# 4. Provision the waypoint proxy (required for L7 authz)
kubectl apply -f waypoints/

# 5. Apply L7 AuthorizationPolicies through the waypoint
kubectl apply -f authz-policies/

# 6. Restart workloads so traffic gets intercepted by ztunnel
kubectl -n default rollout restart deployment --all
```

## How traffic flows in this mesh

```
   Pod A (productpage SA)                              Pod B (details SA)
        │                                                   ▲
        │  1. App opens TCP connection                      │  6. Plaintext to app
        │                                                   │
        ▼                                                   │
   ┌─ Node A iptables (programmed by istio-cni) ─┐         ▲
   │                                              │         │
   │       2. Redirected to ztunnel               │         │
   │       3. ztunnel wraps in HBONE+mTLS         │         │
   │          using Pod A's SPIFFE identity       │         │
   └──────────────┬───────────────────────────────┘         │
                  │ HBONE-tunneled mTLS                     │
                  ▼                                         │
   ┌─ Node B iptables ─┐                                    │
   │                   │                                    │
   │   4. ztunnel verifies Pod A's identity                 │
   │   5. ztunnel forwards plaintext to Pod B               │
   └───────────────────┴────────────────────────────────────┘
```

If a Waypoint is involved (L7 features needed), the path becomes:

```
Pod A → ztunnel → ztunnel → Waypoint Proxy → ztunnel → Pod B
        (mTLS)              (HTTP inspection,
                             AuthorizationPolicy
                             evaluation)
```

## What changes for prod

- **Per-namespace waypoints**, not per-cluster — only the namespaces that
  need L7 features get them, keeping the cost predictable.
- **Multi-cluster mesh** — istiod federation across the eu-central-1 primary
  and the eu-west-1 DR cluster (planned in a future ADR).
- **External authorizers** — JWT validation against AWS Cognito or Auth0
  in the waypoint via `AuthorizationPolicy` with `customRules` referring
  to an external authz server.
- **Telemetry separation** — Tempo for traces (collected via the waypoint
  for L7 hops, ztunnel for L4 hops), separate from Prometheus.

## Mülakatta Bu Soruyu Alırsan

### Q1. "Ambient mode'da bir Pod kendi mTLS sertifikalarını nasıl alıyor — sidecar yoksa kim üretiyor?"

ztunnel her node'da bir DaemonSet olarak çalışır ve **CSR'ı kendi
ServiceAccount'u ile** istiod'a gönderir. istiod sertifika veriyor; ztunnel
o sertifikayı kullanarak **pod ServiceAccount'unun adına** mTLS handshake
yapar (impersonation değil — ztunnel pod identity'sini kanıtlayabilen
SPIFFE referansları taşır). Pod'un kendisi sertifika tutmaz, kuyruk
turunda hiçbir şey değişmez. Trust chain: istiod → node ztunnel → pod
identity proof.

### Q2. "ztunnel pod'u kendisi compromise olursa ne olur?"

ztunnel **node-level** DaemonSet'tir, yani o node'daki tüm pod'ların mTLS
trafiğini görüyor olabilir. Bu mevcut sidecar mode'da bile aynıdır: bir
node compromise olursa o node'daki sidecar'lar da etkilenir. Ambient
mode'un fark yaratmadığı yer burası. Defansif kontrol: AuthorizationPolicy
SPIFFE identity bazlı çalışır, ztunnel kendi başına yetkilendirme
yapamaz; ayrıca ztunnel privileged container değildir, sadece kendi
linux namespace'lerinden yetkilidir. Risk azaltma: NodeSelector ile
hassas pod'ları belirli node'lara izole etmek (örn: payments için
dedicated node group).

### Q3. "Bir namespace ambient mode'a alındığında uygulama kodunda hiçbir değişiklik yapmamak gerçekten doğru mu?"

Evet. ambient label namespace'e konduktan sonra istio-cni iptables
kuralı ekler, ztunnel yeni connection'ı yakalar, mTLS uygular,
karşı tarafta da çözer. Pod'un ne tcpdump çalışsa "encrypted" görür
ne de uygulamada herhangi bir kod değişikliği gerekir. Tek istisna:
host network kullanan pod'lar (DaemonSets like kube-proxy, aws-node)
ambient'ın dışında kalır — bu da AKS / EKS gibi managed setup'larda
böyle olmalı zaten.

### Q4. "Sidecar yoksa Envoy'un sunduğu özellikler — header manipulation, fault injection, retry — nasıl alıyoruz?"

Bunlar **L7 özellikleri**dir, ambient mode bunları **waypoint proxy**
arkasına alır. Bir namespace'in L7'ye ihtiyacı varsa (örneğin
"GET /payments/* sadece JWT iss=auth.biopay.com tarafından imzalı
token ile") o namespace için bir Gateway resource ile waypoint deploy
edilir; istiod ona Envoy config gönderir. L7 trafiği ztunnel → waypoint
→ ztunnel → hedef pod yolunu izler. L4 yeten servislere (örn:
Prometheus scrape, basit gRPC) waypoint dokunulmaz; ekstra hop ödemez.

### Q5. "ztunnel ne kadar bellek tüketir, sidecar mode'a göre tasarruf gerçek mi?"

Tek ztunnel pod node başına ~80–150 MiB tüketir. Sidecar mode'da
50 pod'u olan bir node'da 50 × ~50 MiB = 2.5 GiB sidecar belleği
gider. Ambient'ta aynı node 80–150 MiB ile dolaşır. İlk demo
cluster'larında bile fark görünür; cluster büyüdükçe (100+ pod/node)
tasarruf 10x'lere çıkar. Trade-off: waypoint kullanan namespace
başına +1 Deployment maliyeti var, fakat bu paylaşılan ve seyrektir.
