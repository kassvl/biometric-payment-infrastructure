# =============================================================================
# EKS-managed addons.
#
# Why managed addons instead of self-installed manifests:
#   - AWS picks compatible versions per cluster minor; we don't have to track
#     a Helm chart × CNI version × cluster version compatibility matrix.
#   - In-place updates are observable in the EKS console and via AWS API.
#   - Drift detection: addon configuration is reconciled by EKS, not by us.
#
# Special case: aws-ebs-csi-driver needs an IAM role (the driver's pod
# creates EBS volumes via the AWS API). With IRSA, we pass the IRSA role
# ARN as the `service_account_role_arn` of the addon and EKS annotates the
# ServiceAccount automatically.
# =============================================================================

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  # When version is null, EKS picks the recommended version for the cluster's
  # Kubernetes minor. Pinning here is rare; we prefer EKS's defaults.
  addon_version = each.value.version

  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  configuration_values = each.value.configuration_values
  preserve             = each.value.preserve

  # The aws-ebs-csi-driver addon expects an IRSA role; every other addon
  # in our default set runs without one.
  #
  # When enable_ebs_csi_irsa is false (Lab mode), we pass null and the
  # addon falls back to using the node IAM role for AWS API access — works
  # as long as the node role has EBS permissions, which LabRole does.
  service_account_role_arn = (
    each.key == "aws-ebs-csi-driver" && var.enable_ebs_csi_irsa
    ? aws_iam_role.ebs_csi[0].arn
    : null
  )

  # Addons must wait for at least one node to be Ready, otherwise the
  # CoreDNS deployment will sit in Pending and EKS will mark the addon as
  # degraded. Waiting on the node groups guarantees nodes are up.
  depends_on = [aws_eks_node_group.this]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${each.key}"
    Type = "eks-addon"
  })
}
