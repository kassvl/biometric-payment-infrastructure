# =============================================================================
# Terraform and provider version constraints for the dev environment.
#
# Backend uses a PARTIAL configuration: the bucket name embeds the account ID
# and is supplied at `terraform init` time so we never commit it. All other
# backend settings are constants and are checked into the file.
#
# First-time init (after bootstrap apply):
#
#   ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
#   terraform init -backend-config="bucket=biopay-tfstate-${ACCOUNT}"
#
# Subsequent inits remember the bucket from .terraform/terraform.tfstate.
# =============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    # bucket is supplied via `-backend-config` at init; see header.
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "biopay-tfstate-locks"
    encrypt        = true
    kms_key_id     = "alias/biopay-tfstate"
  }
}
