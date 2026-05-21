# =============================================================================
# VPC Flow Logs → CloudWatch Logs.
#
# Why CloudWatch and not S3:
#   - Queryable via CloudWatch Logs Insights without an extra step.
#   - Native integration with metric filters → CloudWatch Alarms.
#   - Trade-off: more expensive than S3 for very high volumes; for this
#     environment's scale it's the right balance. Long-term retention can
#     be moved to S3 via a CloudWatch subscription if costs grow.
#
# Required by PCI-DSS 10.x (audit logs of network traffic) and DORA forensics.
# =============================================================================

# Conditional creation: a downstream environment can disable flow logs (e.g.,
# in a sandbox), but the default is enabled.
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/${var.project_name}/${var.env}/vpc/flowlogs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.flow_log_kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-vpc-flowlogs"
    Purpose = "vpc-flow-logs"
  })
}

# IAM role assumed by the VPC Flow Logs service to write into CloudWatch.
resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name        = "${local.name_prefix}-vpc-flow-logs"
  description = "Lets the VPC Flow Logs service write to CloudWatch Logs for the ${local.name_prefix} VPC."
  path        = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      # Scope the policy to this VPC's flow log group only.
      Resource = [
        aws_cloudwatch_log_group.flow_logs[0].arn,
        "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
      ]
    }]
  })
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.main.id
  traffic_type         = var.flow_log_traffic_type
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  # Maximum aggregation period is 600s (10m) for CloudWatch destination;
  # 60s gives finer-grained traces at slightly higher cost. We pick 60s
  # so the SOC has minute-level network visibility.
  max_aggregation_interval = 60

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flowlog"
  })
}
