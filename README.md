# PayEye Secure Biometric Payment Infrastructure

[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.9-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS_eu--central--1-FF9900?logo=amazonaws)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Orchestration-EKS_1.30-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![Service Mesh](https://img.shields.io/badge/Mesh-Istio_Ambient-466BB0?logo=istio)](https://istio.io/latest/docs/ambient/)
[![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=githubactions)](https://github.com/kassvl/biometric-payment-infrastructure/actions)
[![Security](https://img.shields.io/badge/Scan-Checkov%20%7C%20tfsec%20%7C%20Trivy-success)](#security--compliance)
[![License](https://img.shields.io/badge/License-Proprietary-lightgrey)](#license)

> Production-grade AWS infrastructure-as-code for **PayEye**, a Polish FinTech that uses
> iris + face biometrics for in-store payments. This repository provisions the secure,
> auditable, and PCI-DSS-aware platform that biometric authentication and payment
> services run on, modeled after the architectural patterns expected of a regulated
> European payment processor.

---

## 1. Why this project exists

PayEye operates in a **regulated payment-processing space** (PSD2, PCI-DSS, GDPR,
EU DORA). Running biometric and card-adjacent workloads requires:

- Strong **network segmentation** so card-handling pods cannot reach the public internet directly
- **Encryption everywhere**: at rest (KMS), in transit (mTLS via service mesh), in state files
- **Auditable change pipeline**: nothing reaches production without a reviewed, scanned, plan-approved PR
- **Identity-bound** access — no long-lived AWS keys inside the cluster
- **Observability** that is good enough to answer regulator questions in minutes, not days

This repository is the codified version of those requirements.

---

## 2. High-level architecture

```
                        ┌───────────────────────────────────────────────────────┐
                        │                   Route 53 (public)                   │
                        │                   ACM (wildcard TLS)                  │
                        └──────────────────────────┬────────────────────────────┘
                                                   │
                                          ┌────────▼────────┐
                                          │   AWS WAF v2    │
                                          │  (managed RG +  │
                                          │   custom rules) │
                                          └────────┬────────┘
                                                   │
                              ┌────────────────────▼────────────────────┐
                              │           Application Load Balancer     │
                              │           (Ingress, public subnets)     │
                              └────────────────────┬────────────────────┘
                                                   │
   ┌───────────────────────────────────────────────▼────────────────────────────────────────────────┐
   │                                  VPC 10.0.0.0/16  (eu-central-1)                               │
   │                                                                                                │
   │   ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐                 │
   │   │ Public  AZ-a       │     │ Private-app AZ-a   │     │ Private-db  AZ-a   │                 │
   │   │ 10.0.1.0/24        │     │ 10.0.10.0/24       │     │ 10.0.20.0/24       │                 │
   │   │ NAT GW + ALB       │     │ EKS nodes + Istio  │     │ Aurora writer      │                 │
   │   └────────────────────┘     └────────────────────┘     └────────────────────┘                 │
   │                                                                                                │
   │   ┌────────────────────┐     ┌────────────────────┐     ┌────────────────────┐                 │
   │   │ Public  AZ-b       │     │ Private-app AZ-b   │     │ Private-db  AZ-b   │                 │
   │   │ 10.0.2.0/24        │     │ 10.0.11.0/24       │     │ 10.0.21.0/24       │                 │
   │   │ NAT GW + ALB       │     │ EKS nodes + Istio  │     │ Aurora reader      │                 │
   │   └────────────────────┘     └────────────────────┘     └────────────────────┘                 │
   │                                                                                                │
   │   VPC Flow Logs ─► CloudWatch ─► (Athena / Security Hub)                                       │
   └────────────────────────────────────────────────────────────────────────────────────────────────┘

   Cross-cutting controls:
     • IRSA (IAM Roles for Service Accounts) — pod-level identity, no static keys
     • External Secrets Operator + AWS Secrets Manager — secret material lives outside Git/etcd
     • GuardDuty + Security Hub — continuous threat detection and CSPM
     • Disaster recovery: warm standby in eu-west-1 (Ireland)
```

---

## 3. Tech stack

| Layer            | Choice                                          | Why                                                                                |
| ---------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| IaC              | **Terraform 1.9** (modular, S3 + DynamoDB)      | Industry standard for AWS, reviewable plans, state locking prevents collisions     |
| Cloud            | **AWS** (`eu-central-1` primary, `eu-west-1` DR) | Frankfurt = EU data residency, lowest latency to Wrocław, GDPR / Schrems II safe   |
| Orchestration    | **Amazon EKS 1.30** (managed node groups)        | Managed control plane reduces operational burden, full Kubernetes API              |
| Service mesh     | **Istio Ambient (ztunnel + waypoint)**           | mTLS without sidecars → less memory, lower CPU, easier upgrades than classic Istio |
| CI/CD            | **GitHub Actions** + Checkov + tfsec + Trivy     | Native to the host platform, secrets via OIDC, no shared CI runners needed         |
| Observability    | **Prometheus + Grafana + Loki** + CloudWatch     | Open-source stack for metrics/logs, CloudWatch for AWS-native and compliance logs  |
| Secret mgmt      | **AWS Secrets Manager** + External Secrets Operator | Secrets stay in Secrets Manager; cluster pulls them with IRSA — never in Git    |
| Identity         | **IRSA** (IAM Roles for Service Accounts)        | Each pod gets a scoped IAM role via OIDC — eliminates long-lived keys              |
| Edge security    | **AWS WAF v2** + AWS Shield Standard             | OWASP Top 10 + custom rate-limit rules at the ALB                                  |
| DNS / TLS        | **Route 53** + **ACM** (wildcard, auto-renew)    | Auto-renewing certs, DNSSEC option for the apex zone                               |
| Data             | **Aurora PostgreSQL** (Multi-AZ, encrypted)      | Multi-AZ with automatic failover, KMS-encrypted at rest, audit logging on          |
| Cache            | **ElastiCache Redis** (in-transit + at-rest enc) | Session and biometric template cache, never on disk in clear                       |

---

## 4. Repository layout (target)

```
payeye-infra/
├── terraform/
│   ├── bootstrap/            # S3 state bucket + DynamoDB lock (chicken-and-egg solver)
│   ├── modules/
│   │   ├── vpc/              # VPC, subnets (3-tier × 2 AZ), NAT GW per AZ, Flow Logs
│   │   ├── eks/              # Cluster, managed node groups, IRSA, OIDC provider, addons
│   │   ├── rds/              # Aurora PostgreSQL Multi-AZ, parameter groups, KMS, backups
│   │   ├── security/         # SGs, GuardDuty, Security Hub, WAF, KMS keys
│   │   ├── dns-tls/          # Route53 zones, ACM wildcard cert, health checks
│   │   └── observability/    # CloudWatch log groups, dashboards, alarms, SNS topics
│   └── environments/
│       ├── dev/              # Smaller node groups, single-AZ data, cheap
│       └── prod/             # HA, Multi-AZ, full retention, FinTech-grade
├── kubernetes/
│   ├── namespaces/           # Tenant + system namespace declarations
│   ├── istio/                # Ambient mesh installation, waypoint proxies, AuthZ policies
│   ├── workloads/            # Application Helm releases / kustomizations
│   ├── external-secrets/     # ESO setup + ClusterSecretStore for Secrets Manager
│   └── policies/             # OPA/Kyverno policies, NetworkPolicies, PodSecurity
├── .github/workflows/        # terraform-plan, terraform-apply, security-scan
├── monitoring/
│   ├── prometheus/rules/     # Alerting rules (latency SLO, error budget, infra)
│   └── grafana/dashboards/   # JSON dashboards for app + cluster + AWS
├── docs/
│   ├── adr/                  # Architecture Decision Records
│   └── runbooks/             # On-call procedures (DB failover, cluster upgrade, incident IR)
├── CLAUDE.md                 # AI-pair-programmer working context for this repo
└── README.md                 # ← you are here
```

---

## 5. Security & compliance

This repository is designed with the following frameworks in mind. Every module
ships with controls mapped to a control objective; see each module's README for
the explicit mapping.

- **PCI-DSS v4.0** — network segmentation, encryption, logging, key management
- **GDPR / Schrems II** — EU-only data residency (Frankfurt + Dublin DR)
- **EU DORA** — operational resilience, incident reporting, third-party risk
- **CIS AWS Foundations Benchmark** — automated checks via Security Hub
- **NIST 800-53 (moderate)** — selected control families for change management

CI runs three independent scanners on every PR:

| Scanner    | What it catches                                                      |
| ---------- | -------------------------------------------------------------------- |
| Checkov    | Misconfigured AWS resources (public S3, unencrypted DBs, open SGs)   |
| tfsec      | Terraform-specific security smells, least-privilege IAM violations   |
| Trivy      | Container image CVEs and IaC misconfigs in Dockerfiles + manifests   |

A failing scanner blocks merge. There is no override path that does not require
a Security review approval.

---

## 6. Getting started

> The repository is bootstrapping. Modules ship in dependency order:
> `bootstrap → vpc → security → eks → rds → observability → dns-tls`.

```bash
# Clone
git clone https://github.com/kassvl/biometric-payment-infrastructure.git
cd biometric-payment-infrastructure

# Sign in to AWS (SSO recommended; IAM user with MFA acceptable)
aws sso login --profile payeye-admin

# Bootstrap remote state (one-time per account)
cd terraform/bootstrap
terraform init
terraform plan
terraform apply

# After bootstrap, every other module uses the S3 backend
cd ../environments/dev
terraform init
terraform plan
```

---

## 7. License

Proprietary — © PayEye Sp. z o.o. (portfolio replica by [@kassvl](https://github.com/kassvl)).
This is a **portfolio / educational reproduction** of the architectural patterns a
real PayEye-class FinTech infrastructure would follow. It is not affiliated with
PayEye Sp. z o.o. and provisions no production PayEye systems.

---

## 8. Maintainer

[@kassvl](https://github.com/kassvl) — DevOps / Cloud engineering portfolio,
aimed at the Wrocław / Polish FinTech market.
