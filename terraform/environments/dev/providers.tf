# =============================================================================
# AWS provider configuration for the dev environment.
#
# `default_tags` apply to every resource the provider manages. Modules also
# merge their own `local.common_tags` on top of these — AWS resolution rules
# let resource-level tags override default_tags, so module tags win when
# the same key appears.
# =============================================================================

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.env
      ManagedBy   = "Terraform"
      Repository  = "kassvl/biometric-payment-infrastructure"
      Composition = "environments/${var.env}"
    }
  }
}
