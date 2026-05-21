# =============================================================================
# Terraform and provider version constraints for the EKS module.
#
# tls provider is added because we use `data.tls_certificate` to fetch the
# OIDC issuer's thumbprint dynamically. Hard-coding AWS's root thumbprint
# would silently break when AWS rotates the root CA.
# =============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
