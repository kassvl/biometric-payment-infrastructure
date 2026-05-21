# `terraform/bootstrap/`

> **One-time module.** Solves the chicken-and-egg problem of "where do I store
> the state file for the module that creates the state bucket?"

## What this module creates

| Resource                   | Purpose                                                                                  |
| -------------------------- | ---------------------------------------------------------------------------------------- |
| S3 bucket (versioned, KMS) | Remote Terraform state for every other module/environment in this repo.                  |
| S3 access-log bucket       | Receives all read/write events on the state bucket — required for PCI-DSS audit trail.   |
| DynamoDB table             | State locking; prevents two engineers running `terraform apply` at the same time.        |
| KMS CMK (optional)         | Customer-managed key for state encryption — gives us key rotation and grant control.     |
| Bucket policies            | Block public access, enforce TLS-only, deny unencrypted PUTs.                            |

## How it differs from every other module

This module **uses a local backend** (`backend "local"` in `versions.tf`), because
no remote backend exists yet when it runs. After `terraform apply` succeeds, the
generated outputs (bucket name, DynamoDB table name, KMS key ARN) feed every
other environment's `backend.tf`.

The full implementation is added in the `infra(bootstrap):` commit and includes
the module's own `README.md` with the **"Mülakatta Bu Soruyu Alırsan"** Q&A
section explaining S3 state security, DynamoDB locking semantics, and recovery
from accidental state file deletion.
