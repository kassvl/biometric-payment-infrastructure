# =============================================================================
# Managed node groups + launch templates.
#
# We use a launch template per node group so we can pin three things EKS
# would otherwise leave at defaults:
#   1. EBS root volume encrypted with our KMS key (or account default).
#   2. IMDSv2 required (http_tokens = "required") — blocks SSRF that targets
#      the EC2 metadata service.
#   3. Tags propagated to the underlying EBS volume + ENI for billing.
#
# The node group references the launch template by ID + version=$Latest. AWS
# handles AMI selection per ami_type/cluster_version, so we do NOT pin an
# explicit AMI ID — that responsibility stays with EKS so security patches
# arrive automatically when the node group rolls.
# =============================================================================

# -----------------------------------------------------------------------------
# Launch template per node group.
# -----------------------------------------------------------------------------
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name        = "${local.name_prefix}-eks-${each.key}"
  description = "Launch template for the ${each.key} managed node group in ${local.cluster_name}."

  # Block-device mapping for the root volume.
  # gp3 is cheaper and faster than gp2; encryption is enforced.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = each.value.disk_size_gib
      encrypted             = true
      kms_key_id            = var.node_disk_kms_key_arn
      delete_on_termination = true
    }
  }

  # Force IMDSv2; tokens with hop-limit 2 so the kubelet can reach IMDS
  # through the ENI but containers cannot via SSRF chains.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Detailed monitoring (1-min metrics) is on per node group so we can see
  # CPU steal and saturation in CloudWatch without waiting for the 5-minute
  # default aggregation.
  monitoring {
    enabled = true
  }

  # Propagate our tags to every resource the launch template creates.
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name}-${each.key}-node"
      NodeGroup = each.key
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name}-${each.key}-volume"
      NodeGroup = each.key
    })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(local.common_tags, {
      Name      = "${local.cluster_name}-${each.key}-eni"
      NodeGroup = each.key
    })
  }

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-eks-${each.key}-lt"
    NodeGroup = each.key
  })

  # Launch template content can change in place (instance shape, AMI hint
  # via type, EBS settings). EKS rolls the node group when the template's
  # latest version moves; create_before_destroy on the LT itself is unsafe
  # because it would orphan running nodes from their definition.
  lifecycle {
    create_before_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Managed node groups.
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-${each.key}"
  node_role_arn   = local.effective_node_role_arn
  subnet_ids      = local.node_subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  ami_type       = each.value.ami_type

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  # Allow up to one extra node above desired during a rolling update so the
  # group does not drop below desired while a node is being replaced.
  update_config {
    max_unavailable = 1
  }

  # Bind the launch template. version = $Latest so each apply uses the
  # latest LT version this same Terraform stack created.
  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # Node role policy attachments must exist before the node group is created.
  # When using a pre-existing role (Lab mode), the attachments are not
  # created by this module — depends_on resolves to an empty list there,
  # which is fine because the pre-existing role already has the policies.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ssm_managed,
  ]

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-${each.key}"
    NodeGroup = each.key
  })

  # Ignoring desired_size lets HPA / Cluster Autoscaler / Karpenter mutate
  # it without Terraform fighting them on every apply. min/max stay sticky.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
