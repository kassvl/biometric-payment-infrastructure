# =============================================================================
# Locals: subnet maps keyed by AZ + common tags.
#
# We key subnets by AZ name (not by index) so reordering var.azs cannot
# silently move resources to different subnets. for_each over a map gives
# Terraform stable resource addresses across plans.
# =============================================================================

locals {
  # Cross-check: lengths of the three CIDR lists must match the AZ list.
  # Terraform does not allow validation across multiple variables, so we
  # encode the contract here and trip an explicit error if violated.
  _az_count                  = length(var.azs)
  _public_cidr_count         = length(var.public_subnet_cidrs)
  _private_app_cidr_count    = length(var.private_app_subnet_cidrs)
  _private_db_cidr_count     = length(var.private_db_subnet_cidrs)
  _validate_subnet_cidrs_len = local._public_cidr_count == local._az_count && local._private_app_cidr_count == local._az_count && local._private_db_cidr_count == local._az_count
  # The expression below evaluates to a string only used to fail validation;
  # `regex` returns an error if the input does not match.
  _ = regex(
    "^TRUE$",
    local._validate_subnet_cidrs_len ? "TRUE" : "FALSE_each_subnet_cidr_list_must_have_one_entry_per_az"
  )

  # Subnet maps. Key = AZ name; Value = CIDR.
  public_subnets_by_az = {
    for i, az in var.azs : az => var.public_subnet_cidrs[i]
  }

  private_app_subnets_by_az = {
    for i, az in var.azs : az => var.private_app_subnet_cidrs[i]
  }

  private_db_subnets_by_az = {
    for i, az in var.azs : az => var.private_db_subnet_cidrs[i]
  }

  # NAT Gateway map.
  #   - single_nat_gateway = true  → exactly one NAT GW (use the first AZ).
  #   - single_nat_gateway = false → one NAT GW per AZ.
  nat_gateway_azs = (
    !var.enable_nat_gateway
    ? []
    : (var.single_nat_gateway ? [var.azs[0]] : var.azs)
  )
  nat_gateways_by_az = { for az in local.nat_gateway_azs : az => az }

  # Common tags applied to every resource produced by this module.
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.env
      Module      = "vpc"
      ManagedBy   = "Terraform"
      Repository  = "kassvl/biometric-payment-infrastructure"
    },
    var.extra_tags,
  )

  name_prefix = "${var.project_name}-${var.env}"
}
