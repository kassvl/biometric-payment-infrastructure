# =============================================================================
# Provider and backend pinning for the bootstrap module.
#
# This is the only Terraform module in the entire repo that uses a LOCAL
# backend. Every other module/environment uses the S3 backend created here.
#
# Migration path after first `terraform apply`:
#   1. Copy `state_bucket_id`, `dynamodb_table_name`, and `kms_key_alias`
#      from the apply output.
#   2. Replace the `backend "local"` block below with `backend "s3"` (a
#      ready-to-paste snippet is exposed as `output.backend_config_snippet`).
#   3. Run `terraform init -migrate-state` and confirm the move.
#   4. Commit the updated backend block.
# =============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  # Tags that AWS supports as resource-level default tags.
  # Resource-specific tags are still merged on top via local.common_tags.
  default_tags {
    tags = {
      Project    = var.project_name
      ManagedBy  = "Terraform"
      Repository = "kassvl/biometric-payment-infrastructure"
      Module     = "bootstrap"
    }
  }
}
