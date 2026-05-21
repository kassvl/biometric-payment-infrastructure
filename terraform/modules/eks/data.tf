# =============================================================================
# Data sources for the EKS module.
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# OIDC issuer thumbprint.
#
# When we create the OpenID Connect provider for IRSA, we have to supply the
# SHA-1 thumbprint of the OIDC issuer's TLS certificate. AWS rotates the
# root CA periodically; hard-coding the thumbprint silently breaks IRSA on
# rotation. Reading the thumbprint at plan time keeps us in sync.
#
# tls_certificate.oidc.url depends on the cluster being created (the issuer
# URL is an output of aws_eks_cluster), so this data source is evaluated
# AFTER the cluster apply finishes. That means the OIDC provider resource
# (which uses this thumbprint) cannot be created in the same apply that
# creates the cluster — Terraform plans correctly because of the implicit
# dependency through the cluster output.
# -----------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
