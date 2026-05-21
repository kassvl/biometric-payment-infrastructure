# =============================================================================
# Locals: cluster name, subnet fallback, common tags, OIDC issuer parsing.
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  cluster_name = coalesce(
    var.cluster_name_override,
    "${var.project_name}-${var.env}-eks",
  )
  name_prefix = "${var.project_name}-${var.env}"

  # Default node-group subnets to the control-plane subnets when not given.
  # In a private-app-only cluster, the operator typically wants both planes
  # in the same set of private subnets.
  node_subnet_ids = coalesce(var.node_subnet_ids, var.control_plane_subnet_ids)

  # OIDC issuer URL → host (e.g. "oidc.eks.eu-central-1.amazonaws.com/id/ABC...")
  # is what IAM trust policies match against, NOT the full URL with scheme.
  oidc_issuer_url  = aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_issuer_host = replace(local.oidc_issuer_url, "https://", "")

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.env
      Module      = "eks"
      ManagedBy   = "Terraform"
      Repository  = "kassvl/biometric-payment-infrastructure"
      Cluster     = local.cluster_name
    },
    var.extra_tags,
  )
}
