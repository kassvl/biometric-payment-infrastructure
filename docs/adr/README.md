# `docs/adr/` — Architecture Decision Records

Each ADR is a numbered Markdown file:

```
docs/adr/
├── 0001-aws-as-the-only-cloud-provider.md
├── 0002-region-eu-central-1-primary-eu-west-1-dr.md
├── 0003-eks-managed-node-groups-not-self-managed.md
├── 0004-istio-ambient-mesh-not-classic-sidecar.md
├── 0005-aurora-postgres-multi-az-not-rds-multi-az.md
├── 0006-external-secrets-operator-with-aws-secrets-manager.md
├── 0007-irsa-no-static-credentials-in-cluster.md
├── 0008-terraform-module-layout-and-state-strategy.md
└── 0009-three-scanner-pre-merge-gate-checkov-tfsec-trivy.md
```

(File numbers and topics above are the planned set; ADRs are added as decisions
are made.)

## Format

Every ADR follows the **Michael Nygard format** — short and disciplined:

```markdown
# ADR-NNNN: <decision title>

- **Status**: Proposed | Accepted | Superseded by ADR-XXXX | Deprecated
- **Date**: YYYY-MM-DD
- **Decider(s)**: <names / roles>

## Context
What problem is being solved? What are the forces in play (tech, regulatory, organizational)?

## Decision
What did we decide to do? State it as an action ("We will use ...").

## Consequences
What becomes easier? What becomes harder? What new risks did we take on?
What did we explicitly choose **not** to do, and why?
```

## Status lifecycle

```
Proposed ─► Accepted ─► (lives forever)
                    └─► Superseded by ADR-NNNN  (the new ADR explains the change)
```

ADRs are **never deleted or rewritten**. They are immutable history. If a
decision is reversed, the new ADR references and supersedes the old one,
and the old one's status is updated to `Superseded by ADR-NNNN`.
