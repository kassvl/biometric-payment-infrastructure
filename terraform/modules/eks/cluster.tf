# =============================================================================
# EKS cluster, control-plane log group, and OIDC identity provider for IRSA.
# =============================================================================


# -----------------------------------------------------------------------------
# Control-plane log group.
#
# EKS requires the log group name to be EXACTLY /aws/eks/<cluster-name>/cluster.
# If the group does not exist when the cluster is created, EKS creates it
# without our retention/KMS settings — so we create it here first and the
# cluster picks it up.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = var.cluster_log_kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "/aws/eks/${local.cluster_name}/cluster"
    Purpose = "eks-control-plane-logs"
  })
}


# -----------------------------------------------------------------------------
# Cluster.
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  # Stream every requested control-plane log type to the log group above.
  enabled_cluster_log_types = tolist(var.cluster_log_types)

  vpc_config {
    subnet_ids              = var.control_plane_subnet_ids
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    # The cluster security group is created and managed by EKS itself.
  }

  # Envelope-encrypt Kubernetes secrets with our CMK if one was supplied.
  # When cluster_encryption_kms_key_arn is null, we omit the block entirely
  # (etcd is still encrypted with AWS-managed keys at the storage layer).
  dynamic "encryption_config" {
    for_each = var.cluster_encryption_kms_key_arn == null ? [] : [1]

    content {
      provider {
        key_arn = var.cluster_encryption_kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  # The cluster role policy attachments must exist before the cluster is
  # created — EKS validates the role at create time. Listing the dependency
  # is explicit so a future refactor cannot accidentally race.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}


# -----------------------------------------------------------------------------
# OIDC identity provider — the federation point for IRSA.
#
# Every IAM role intended to be assumed by a pod has a trust policy that
# references this provider's ARN and conditions on the OIDC issuer's
# subject and audience claims.
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc"
  })
}
