# CLAUDE.md — Project Context for AI Pair Programmers

> Working context for any LLM-driven assistant (Claude Code, Kiro CLI, Copilot,
> etc.) collaborating on this repository. Read this **before** writing any code.
> Conventions here override generic best-practice defaults.

---

## 1. Identity

| Field             | Value                                                                                |
| ----------------- | ------------------------------------------------------------------------------------ |
| Project           | PayEye Secure Biometric Payment Infrastructure                                       |
| Subject company   | PayEye Sp. z o.o. — Polish FinTech, iris + face biometric in-store payments         |
| Domicile          | Wrocław, Poland                                                                      |
| Repo nature       | **Portfolio replica** of a regulated FinTech AWS platform                            |
| Primary region    | `eu-central-1` (Frankfurt) — EU data residency, low latency to Wrocław               |
| Disaster recovery | `eu-west-1` (Ireland) — warm standby                                                  |
| Maintainer        | [@kassvl](https://github.com/kassvl) (`melture33@gmail.com`)                          |
| Audience          | Wrocław/Polish FinTech hiring managers, DevOps interviewers, technical reviewers     |

The audience matters: **every module ships with an interview Q&A section** so
the maintainer can defend each decision under technical scrutiny.

---

## 2. Architectural decisions (the spine)

These are the foundational choices. Treat them as fixed unless explicitly
revisited via an ADR in `docs/adr/`.

### 2.1 Why AWS

| Alternative considered | Why we did not pick it                                                              |
| ---------------------- | ----------------------------------------------------------------------------------- |
| GCP                    | Smaller EU FinTech footprint; the Polish job market predominantly demands AWS.      |
| Azure                  | Strong in enterprise IT but weaker in PCI-DSS-aware reference architectures.        |
| Multi-cloud            | Triples the surface area of IAM, networking, and observability — wrong for portfolio scope. |

### 2.2 Why `eu-central-1` primary, `eu-west-1` DR

- **Frankfurt** = EU (Germany) data residency; satisfies GDPR + Schrems II concerns
  for payment data leaving the EU.
- Closer to Wrocław than Ireland → slightly lower customer-facing latency.
- **Ireland** as DR gives a second EU jurisdiction — if Frankfurt is partitioned,
  failover does not require re-papering data-export agreements.

### 2.3 Why EKS (managed) over self-managed Kubernetes

- We do not want to own the control plane: kube-apiserver patches, etcd backups,
  certificate rotation are commodity work that AWS does correctly.
- IRSA depends on the EKS-issued OIDC discovery document — works out of the box.
- **Trade-off accepted:** EKS pricing per cluster, less freedom on CNI / API server
  flags. Acceptable for a regulated workload that benefits from "boring".

### 2.4 Why Istio Ambient mesh, not classic sidecars

| Concern                   | Sidecars (classic)                          | Ambient (ztunnel + waypoint)                          |
| ------------------------- | ------------------------------------------- | ----------------------------------------------------- |
| Memory per pod            | +50–200 MB Envoy                            | 0 (proxy is per-node)                                 |
| Pod startup latency       | Init container delay                        | None                                                  |
| L7 features when needed   | Always on (paying for L7 even at L4)        | Opt-in via waypoint (pay only where used)             |
| Mesh upgrade impact       | Re-roll every pod                           | Update ztunnel DaemonSet only                         |
| Maturity                  | Long-stable                                 | GA in Istio 1.22+ — newer, but proven                 |

The decision is documented as **ADR-0004** when the ADR file is added.

### 2.5 Why Aurora PostgreSQL Multi-AZ over RDS PostgreSQL

- Aurora's storage layer replicates data across **3 AZs at the storage level**;
  failover is faster and reader endpoints scale horizontally without app changes.
- Backup is continuous to the storage tier — point-in-time recovery is fine-grained.
- Cost is higher than vanilla RDS, but matches the FinTech reliability bar.

### 2.6 Why External Secrets Operator + AWS Secrets Manager (not SealedSecrets, Vault)

- **SealedSecrets** keeps secrets in Git (encrypted), but rotation requires re-sealing;
  unsuitable for credential rotation policies a regulator expects.
- **HashiCorp Vault** is excellent but adds an entire HA cluster to operate; not
  justified when AWS Secrets Manager is already in scope and audited.
- **ESO + Secrets Manager** = secrets never enter Git or etcd in clear, rotation
  is native to Secrets Manager, audit trail is in CloudTrail.

### 2.7 Why IRSA (IAM Roles for Service Accounts), no static keys

- Static IAM keys in a cluster are a primary breach vector (Capital One 2019, etc.).
- IRSA federates Kubernetes service-account JWTs to IAM via OIDC. Each pod assumes
  a **scoped** role with a short-lived (1-hour) credential, automatically rotated.
- **Hard rule:** if a module needs to write `aws_access_key_id` anywhere, that is
  a defect — file an issue, do not commit.

### 2.8 Why Terraform with S3 + DynamoDB backend, not Terraform Cloud

- Terraform Cloud adds a vendor outside AWS that processes our plan output
  (which contains resource diffs and sometimes sensitive values).
- S3 + DynamoDB is **inside our AWS account**, encrypted with our KMS key,
  audited via CloudTrail. No third party in the data path.
- We accept that we have to wire OIDC → AWS in GitHub Actions ourselves.

---

## 3. PCI-DSS posture — what this repo is and is not

### 3.1 Scope statement

This repository describes the **shared infrastructure** that hosts payment-adjacent
services. It is therefore in scope for:

- **PCI-DSS v4.0 Requirements 1, 2, 3, 4, 7, 8, 10, 11, 12** (network, hardening,
  encryption at rest + in transit, access control, audit logging, testing, policy).

It is **out of scope** for:

- **Requirement 6** (secure software development) — that lives in the application repos.
- **Requirement 9** (physical security) — handled by AWS as a Level 1 PCI Service Provider.
- **Requirement 5** (anti-malware) where AWS GuardDuty Malware Protection covers EBS-attached workloads.

### 3.2 Concrete controls expressed in this repo

| PCI Requirement                                  | Where in this repo                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------- |
| 1.x — Network segmentation, firewall rules       | `terraform/modules/vpc/`, `terraform/modules/security/` (SGs), `kubernetes/policies/` (NetworkPolicy + Istio AuthZ) |
| 2.x — System hardening, no defaults              | EKS managed AMIs auto-patched; default SG stripped of rules; IAM password policy. |
| 3.x — Encryption of stored data (PAN, etc.)      | KMS CMKs (`security/`), Aurora storage encryption, S3 bucket SSE-KMS.            |
| 4.x — Encryption in transit                      | mTLS via Istio Ambient (mesh-wide STRICT), `rds.force_ssl=1`, ALB HTTPS-only, S3 deny-non-TLS. |
| 7.x — Need-to-know access                        | IRSA scoped roles per pod, IAM least-privilege, K8s RBAC.                        |
| 8.x — Identification & authentication            | IAM password policy, MFA enforcement (via SCP), OIDC for users.                  |
| 10.x — Logging & monitoring                      | CloudTrail (immutable + object-locked), VPC Flow Logs, EKS control plane logs, WAF logs, GuardDuty findings to Security Hub. |
| 11.x — Regular security testing                  | Checkov + tfsec + Trivy in CI; AWS Inspector for image vuln scans; Security Hub continuous checks. |
| 12.x — Information security policy               | This document + `docs/adr/` decisions + per-module READMEs.                      |

### 3.3 Non-goals (explicit)

- **PA-DSS / payment application certification** — out of scope.
- **A real audited environment** — this is a portfolio replica; no real card data
  ever enters infrastructure provisioned from this repo.
- **HSM for key management** — AWS KMS is sufficient for FIPS 140-2 Level 3
  with `aws:kms` (CloudHSM-backed for the highest tier — out of scope here).

---

## 4. Coding conventions

### 4.1 Terraform

- **One resource per logical concern** per file when a module grows past ~150 lines.
- File naming: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, optional
  `iam.tf`, `data.tf`, `locals.tf`.
- **Provider versions are pinned** with `~>` to a minor version in `versions.tf`.
- **No `provider {}` block inside reusable modules.** Providers come from the
  composing environment.
- `for_each` over `count` for collections of named things (subnets, AZs).
- Variable names are `snake_case`; descriptions are full sentences.
- **Every variable has a `type` and a `description`.** No bare `variable "x" {}`.
- Tags are produced by a `local.common_tags` map and merged into every resource:

  ```hcl
  locals {
    common_tags = {
      Project            = "payeye"
      Environment        = var.env
      Owner              = "platform-team"
      CostCenter         = "platform"
      DataClassification = var.data_classification
      ManagedBy          = "Terraform"
      Repo               = "kassvl/biometric-payment-infrastructure"
    }
  }
  ```

- `terraform fmt -recursive` is mandatory before commit. CI re-checks it.

### 4.2 Kubernetes manifests

- Every resource has `metadata.labels.app.kubernetes.io/{name,part-of,managed-by,version}`.
- No `kind: Secret` with literal data committed. Use `ExternalSecret`.
- No `imagePullPolicy: Always` with `:latest`. Pin a tag, set `imagePullPolicy: IfNotPresent`.
- `resources.requests` and `resources.limits` are required on every container.
- `securityContext.runAsNonRoot: true` and `readOnlyRootFilesystem: true` unless
  the workload genuinely cannot tolerate it (write a comment if not).

### 4.3 Commit messages

Conventional Commits, but written like a human:

```
<type>(<scope>): <what + why>

Optional 1–2 sentence body explaining the technical rationale.
```

Types: `feat`, `infra`, `ci`, `docs`, `fix`, `security`, `refactor`.

Bad: `update files`, `add terraform`, `WIP`, `fix stuff`.

### 4.4 Pull request hygiene

- One concern per PR. Don't mix `infra(vpc):` with `ci(pipeline):`.
- PR description includes: what changed, why, what was tested, plan output (for Terraform).
- Plan output goes in a collapsible `<details>` block, never in the PR title.
- Failing scanner blocks merge. Green is the only path forward.

---

## 5. Working principles for AI pair programmers

These rules apply to **any** LLM that contributes code to this repo, including
the maintainer's own AI workflow.

1. **No placeholder code.** Do not write `# TODO: implement` in something that
   ships in a commit. Either implement it fully, or stage a smaller commit that
   sets up structure with explicit `README.md` notes about what comes next.

2. **Read before writing.** Before changing a file, open the existing file and
   nearby files. Match the style, the variable naming, the comment density.

3. **Verify after writing.** After each file:
   - Read it back (`cat` / file-read tool).
   - Run `terraform fmt -check` for HCL changes.
   - Run `terraform validate` once a module is composable.
   - For YAML, run `kubectl --dry-run=client -f` or `kubeconform`.

4. **Sequential thinking on multi-resource modules.** Before writing the VPC
   module, list the resources in dependency order, then write them in that order.
   Do not jump around.

5. **Stop on security smells.** If a tool would write something like:
   - A bucket without `block_public_access`,
   - A SG with `0.0.0.0/0` ingress on anything other than 80/443,
   - An IAM policy with `Action: "*", Resource: "*"`,
   - A `Secret` with literal credentials,

   ...stop, document the concern in the chat with the maintainer, and propose
   a safer alternative. Do not commit.

6. **Every module ships with "Mülakatta Bu Soruyu Alırsan" Q&A.** This is a
   non-negotiable section in the module's `README.md` containing 5–10 questions
   an interviewer might ask, with concise, technically correct answers. Examples
   of question types:

   - Why CIDR `/16` not `/20`?
   - Why NAT Gateway per AZ instead of one shared?
   - What happens if the state bucket is accidentally deleted?
   - How does IRSA prevent credential leak vs static keys?
   - How does Aurora failover differ from RDS PostgreSQL Multi-AZ?

7. **Costs are part of the design.** When a decision has a non-trivial monthly
   bill, mention it in the module README's "Trade-offs" section. NAT Gateway
   per AZ vs shared is the canonical example.

8. **Commit cadence.** One logical change = one commit. Push after every commit.
   Show `git log --oneline -5` after each push.

9. **Never commit:** state files, `*.tfvars` (except `*.example.tfvars`), `.env`,
   any file containing an AWS account ID hardcoded in source, any private key.

10. **Language for commits and code comments is English.** The conversation with
    the maintainer can be Turkish, but anything that ends up in the repo is in
    English so the work is portable across reviewers.

---

## 6. Build & verify cheat sheet

```bash
# Format
terraform fmt -recursive

# Lint a module
cd terraform/modules/vpc
terraform init -backend=false
terraform validate

# Lint an environment (full init with backend)
cd terraform/environments/dev
terraform init
terraform validate
terraform plan

# Security scan
checkov -d terraform/
tfsec terraform/
trivy config terraform/

# Kubernetes
kubeconform -strict -summary kubernetes/

# Cost preview (when Infracost is wired up)
infracost breakdown --path terraform/environments/dev
```

---

## 7. Out-of-scope reminders

- Application source code (the actual payment service) is in **separate repos**.
- This repo does not provision live PayEye production. It models the patterns.
- We do not commit `terraform.tfstate`, kubeconfigs, or any cloud credentials.

---

## 8. Glossary

| Term         | Meaning                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------- |
| IRSA         | IAM Roles for Service Accounts — federates K8s SA tokens to IAM via OIDC.                |
| ESO          | External Secrets Operator — pulls secrets from a provider (Secrets Manager) into K8s.    |
| ALB          | Application Load Balancer — L7 AWS load balancer.                                        |
| ACM          | AWS Certificate Manager — managed TLS cert issuance.                                     |
| WAF v2       | AWS Web Application Firewall, attached to ALB or CloudFront.                             |
| GuardDuty    | AWS-native threat detection on logs and runtime signals.                                 |
| Security Hub | AWS-native CSPM / aggregator that runs CIS / PCI / NIST checks.                          |
| KMS CMK      | Customer-Managed Key — a CMK we own, rotate, and grant on, vs an AWS-managed key.        |
| OIDC         | OpenID Connect — token-based federation between an issuer (EKS, GitHub) and a verifier (IAM). |
| ADR          | Architecture Decision Record — short, immutable note explaining why a decision was made. |
| ztunnel      | Istio Ambient's per-node L4 proxy (one per node, runs as DaemonSet).                     |
| Waypoint     | Istio Ambient's optional per-namespace L7 proxy.                                          |
| RPO / RTO    | Recovery Point Objective / Recovery Time Objective — data loss / downtime tolerances.   |
