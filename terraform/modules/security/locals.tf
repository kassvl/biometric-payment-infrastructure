# =============================================================================
# Locals: KMS key catalog, common tags, validation cross-checks.
# =============================================================================

locals {
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.name
  name_prefix = "${var.project_name}-${var.env}"

  # ---------------------------------------------------------------------------
  # KMS key catalog. Each entry defines what service principals are allowed
  # to use the key. Adding a new domain here is the single point of change
  # if a future module needs its own CMK.
  # ---------------------------------------------------------------------------
  kms_key_catalog = {
    logs = {
      description = "CMK for ${local.name_prefix} CloudWatch Logs encryption (VPC Flow Logs, EKS audit, WAF, app logs)."
      services = [
        "logs.${local.region}.amazonaws.com",
        "logs.amazonaws.com",
      ]
    }

    secrets = {
      description = "CMK for ${local.name_prefix} AWS Secrets Manager secrets (RDS master password, OIDC client secrets, app credentials)."
      services = [
        "secretsmanager.amazonaws.com",
      ]
    }

    rds = {
      description = "CMK for ${local.name_prefix} Aurora PostgreSQL storage encryption and Performance Insights."
      services = [
        "rds.amazonaws.com",
      ]
    }

    ebs = {
      description = "CMK for ${local.name_prefix} EBS volume encryption (EKS worker nodes, any future EC2)."
      services = [
        "ec2.${local.region}.amazonaws.com",
        "ec2.amazonaws.com",
      ]
    }
  }

  # Filter the catalog by the caller's selection (default = all four).
  kms_keys_selected = {
    for name, cfg in local.kms_key_catalog :
    name => cfg if contains(var.kms_keys_to_create, name)
  }

  # ---------------------------------------------------------------------------
  # Cross-variable validation: when VPC endpoints are enabled, all VPC inputs
  # must be present. We trip a regex-based hard error if any required input
  # is missing — failing fast at plan time is much better than late at apply.
  # ---------------------------------------------------------------------------
  _vpc_endpoint_inputs_complete = (
    !var.enable_vpc_endpoints ||
    (
      var.vpc_id != null &&
      var.vpc_cidr_block != null &&
      length(var.private_app_subnet_ids) > 0 &&
      length(var.private_app_route_table_ids) > 0
    )
  )
  _ = regex(
    "^OK$",
    local._vpc_endpoint_inputs_complete ? "OK" : "ERROR_enable_vpc_endpoints_requires_vpc_id_vpc_cidr_block_private_app_subnet_ids_and_private_app_route_table_ids"
  )

  # ---------------------------------------------------------------------------
  # Common tags applied to every resource.
  # ---------------------------------------------------------------------------
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.env
      Module      = "security"
      ManagedBy   = "Terraform"
      Repository  = "kassvl/biometric-payment-infrastructure"
    },
    var.extra_tags,
  )
}
