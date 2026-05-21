# `terraform/environments/dev/`

> Development environment composition. **Cost-optimized**, lower retention,
> smaller node groups. Used by engineers and CI for integration testing.

## Backend

```hcl
# backend.tf (committed)
terraform {
  backend "s3" {
    bucket         = "payeye-tfstate-<account-id>"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "payeye-tfstate-locks"
    encrypt        = true
    kms_key_id     = "alias/payeye-tfstate"
  }
}
```

## Module inputs (will be filled)

```hcl
module "vpc" {
  source = "../../modules/vpc"

  env                = "dev"
  cidr_block         = "10.0.0.0/16"
  azs                = ["eu-central-1a", "eu-central-1b"]
  enable_flow_logs   = true
  flow_log_retention = 30
}

module "security" { ... }
module "eks"      { ... }
module "rds"      { ... }
# etc.
```

## Cost guardrails

- Node group: 2× `t3.large` minimum, autoscale to 4×.
- Aurora: single writer + single reader, `db.r6g.large`, **shorter** backup retention (7 days).
- Single NAT Gateway is acceptable in dev (cost < HA in this environment).
- Log retention: 7–30 days across the board.

## What this environment is NOT for

- Performance testing — use a dedicated `staging/` env (not yet scaffolded).
- Customer data — synthetic data only.
- Compliance audits — `prod/` is the audited environment.
