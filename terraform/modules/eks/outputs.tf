# =============================================================================
# Outputs consumed by composing environments and downstream tooling.
# =============================================================================


# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------
output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_version" {
  description = "Kubernetes minor version of the EKS cluster (e.g. '1.30')."
  value       = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL. Used to populate kubeconfig."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA cert presented by the API server. Used to populate kubeconfig.cluster.certificate-authority-data."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group. EKS attaches this to control-plane ENIs and to every worker node."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_log_group_name" {
  description = "Name of the CloudWatch log group receiving control-plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}


# -----------------------------------------------------------------------------
# OIDC / IRSA
# -----------------------------------------------------------------------------
output "oidc_provider_arn" {
  description = "ARN of the IAM OpenID Connect provider for IRSA. Null when enable_irsa_oidc_provider=false."
  value       = try(aws_iam_openid_connect_provider.eks[0].arn, null)
}

output "oidc_provider_url" {
  description = "Full HTTPS URL of the OIDC issuer. Null when enable_irsa_oidc_provider=false."
  value       = try(aws_iam_openid_connect_provider.eks[0].url, null)
}

output "oidc_issuer_host" {
  description = "Hostname (without scheme) of the OIDC issuer. This is what IAM trust policy conditions reference (e.g. <host>:sub). Empty string when enable_irsa_oidc_provider=false."
  value       = local.oidc_issuer_host
}


# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
output "cluster_iam_role_arn" {
  description = "Effective ARN of the IAM role assumed by the EKS control plane. Either the role this module created or the pre-existing role passed via var.cluster_iam_role_arn."
  value       = local.effective_cluster_role_arn
}

output "node_iam_role_arn" {
  description = "Effective ARN of the IAM role attached to worker node EC2 instances. Either the role this module created or the pre-existing role passed via var.node_iam_role_arn."
  value       = local.effective_node_role_arn
}

output "ebs_csi_irsa_role_arn" {
  description = "ARN of the IRSA role assumed by the aws-ebs-csi-driver pod. Null when enable_ebs_csi_irsa=false (the addon then uses the node IAM role for EBS access)."
  value       = try(aws_iam_role.ebs_csi[0].arn, null)
}


# -----------------------------------------------------------------------------
# Node groups
# -----------------------------------------------------------------------------
output "node_group_names" {
  description = "Map of node-group key (system, app, ...) -> AWS-side node group name."
  value       = { for k, ng in aws_eks_node_group.this : k => ng.node_group_name }
}

output "node_group_arns" {
  description = "Map of node-group key -> ARN."
  value       = { for k, ng in aws_eks_node_group.this : k => ng.arn }
}


# -----------------------------------------------------------------------------
# Addons
# -----------------------------------------------------------------------------
output "addon_versions" {
  description = "Map of addon name -> resolved addon version. Useful for noting which version EKS picked when version was left null."
  value       = { for k, a in aws_eks_addon.this : k => a.addon_version }
}


# -----------------------------------------------------------------------------
# kubectl helper
# -----------------------------------------------------------------------------
output "kubeconfig_command" {
  description = "Drop-in command to update the local kubeconfig for kubectl access. Run once per workstation after cluster provisioning."
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${aws_eks_cluster.this.name} --alias ${aws_eks_cluster.this.name}"
}
