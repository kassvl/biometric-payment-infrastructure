# =============================================================================
# Terraform and provider version constraints for the VPC module.
#
# Reusable modules MUST NOT contain a `provider {}` block or a `backend {}`
# block. Provider configuration and the backend live at the composing
# environment (terraform/environments/<env>/) so the same module can be
# consumed by dev, prod, and any future tenancies.
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
