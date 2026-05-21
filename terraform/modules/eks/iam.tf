# =============================================================================
# IAM roles for the EKS module.
#
# Three roles are created here:
#   1. Cluster role  — assumed by the EKS service to manage the control plane.
#   2. Node role     — assumed by EC2 instances in node groups.
#   3. EBS CSI role  — assumed by the aws-ebs-csi-driver pod via IRSA.
#
# Each role has the minimum AWS-managed policies attached. Adding inline
# policies should be deliberate and is documented in the module README.
# =============================================================================


# -----------------------------------------------------------------------------
# (1) Cluster role
#
# count = 0 when var.cluster_iam_role_arn is supplied (Lab mode), so the
# module skips role creation and uses the pre-existing role's ARN instead.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cluster" {
  count = var.cluster_iam_role_arn == null ? 1 : 0

  name        = "${local.name_prefix}-eks-cluster"
  description = "Service role assumed by the EKS control plane for the ${local.cluster_name} cluster."
  path        = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count = var.cluster_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# AmazonEKSVPCResourceController grants the control plane the right to
# attach extra ENIs for security-groups-per-pod and for VPC CNI prefix
# delegation. Required for any cluster that wants to use those features.
resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  count = var.cluster_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
}


# -----------------------------------------------------------------------------
# (2) Node role
#
# count = 0 when var.node_iam_role_arn is supplied (Lab mode).
# -----------------------------------------------------------------------------
resource "aws_iam_role" "node" {
  count = var.node_iam_role_arn == null ? 1 : 0

  name        = "${local.name_prefix}-eks-node"
  description = "Instance role assumed by EC2 worker nodes in the ${local.cluster_name} cluster."
  path        = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# Required by every EKS worker — kubelet and node-level integrations.
resource "aws_iam_role_policy_attachment" "node_worker" {
  count = var.node_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Pull container images from ECR.
resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  count = var.node_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# VPC CNI privileges. With IRSA we'd attach this to a service account instead;
# attaching to the node role is the simpler "node-level CNI" pattern that EKS
# still supports and is the default for managed addons in recent versions.
resource "aws_iam_role_policy_attachment" "node_cni" {
  count = var.node_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# CloudWatch agent on the node — used by Container Insights / SSM.
resource "aws_iam_role_policy_attachment" "node_ssm_managed" {
  count = var.node_iam_role_arn == null ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# -----------------------------------------------------------------------------
# (3) EBS CSI driver IRSA role
#
# The aws-ebs-csi-driver pod runs in kube-system with ServiceAccount
# 'ebs-csi-controller-sa' and needs IAM permissions to create/attach EBS
# volumes. With IRSA, the pod assumes this role via the cluster's OIDC
# issuer — no static credentials in the cluster.
#
# count = 0 when var.enable_ebs_csi_irsa is false (e.g., AWS Academy Learner
# Lab). The aws-ebs-csi-driver addon then falls back to using the node IAM
# role for EBS API access — works as long as the node role has EBS perms,
# which LabRole does.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi_irsa ? 1 : 0

  name        = "${local.name_prefix}-ebs-csi-irsa"
  description = "IRSA role for the aws-ebs-csi-driver pod (kube-system/ebs-csi-controller-sa) in ${local.cluster_name}."
  path        = "/service-roles/"

  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume[0].json

  tags = local.common_tags
}

data "aws_iam_policy_document" "ebs_csi_assume" {
  count = var.enable_ebs_csi_irsa ? 1 : 0

  statement {
    sid     = "EBSCSIDriverAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks[0].arn]
    }

    # Tie the trust to the exact ServiceAccount the addon ships with.
    # OIDC subject format: system:serviceaccount:<namespace>:<sa-name>
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count = var.enable_ebs_csi_irsa ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
