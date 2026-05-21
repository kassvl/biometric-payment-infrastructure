# `.github/workflows/`

CI/CD pipelines. Three workflows run against this repository:

| Workflow                | Trigger                            | What it does                                                                           |
| ----------------------- | ---------------------------------- | -------------------------------------------------------------------------------------- |
| `terraform-plan.yml`    | `pull_request` on `terraform/**`   | `fmt -check`, `init`, `validate`, `plan` — posts the diff as a PR comment.             |
| `terraform-apply.yml`   | `push` to `main` on `terraform/**` | Manual-approval gated `apply` against the targeted environment via OIDC role.          |
| `security-scan.yml`     | Every PR + nightly                  | Checkov, tfsec, Trivy (IaC mode); SARIF upload to GitHub Code Scanning.                |

## Authentication to AWS — no long-lived keys

GitHub Actions assumes an IAM role via **OIDC federation**:

```
GitHub OIDC Provider  ──► IAM trust policy: token.actions.githubusercontent.com
                                            └── sub: repo:kassvl/biometric-payment-infrastructure:ref:refs/heads/main
                                            └── aud: sts.amazonaws.com
                                  ▼
                         IAM Role: biopay-ci-<env>
                                  ▼
                         scoped to the modules its env owns
```

Two roles, separated by privilege:

- `biopay-ci-plan-only` — `terraform plan` permissions; read-only on most resources.
- `biopay-ci-apply-<env>` — `terraform apply` permissions; assumed only by `terraform-apply.yml` after approval.

## Branch protections (configured at the GitHub side, mirrored here for awareness)

- `main` requires:
  - 1+ approving review (DevOps); 2+ for any change to `prod/`.
  - Required checks: `terraform-plan`, `security-scan`, `terraform-fmt`.
  - No force-pushes, no deletions.
  - Linear history enforced.

## Secrets management

There is **no `secrets.<NAME>`-style static secret in this CI**. Every credential
the workflows need is either:
- An OIDC-issued short-lived AWS credential, or
- A reference to AWS Secrets Manager fetched after assuming the OIDC role.
