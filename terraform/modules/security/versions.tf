# =============================================================================
# Terraform and provider version constraints for the security module.
#
# Same contract as every other reusable module: no provider block, no backend
# block. Provider configuration and the backend live at the composing
# environment (terraform/environments/<env>/).
# =============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
