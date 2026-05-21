# =============================================================================
# VPC, Internet Gateway, and default Security Group hardening.
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block = var.cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  # Modern AWS-native instance metadata: do not rely on it inside the VPC,
  # but keep the default "default" tenancy. Dedicated tenancy is materially
  # more expensive and not required for our workloads.
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
    Tier = "network"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway — single, attached to the VPC. Required for public subnets.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Default Security Group hardening.
#
# AWS auto-creates a "default" security group on every VPC with permissive
# self-referencing rules. CIS AWS Foundations 5.4 requires these rules be
# stripped so accidentally landing a resource in the default SG yields no
# implicit network access. We import-by-resource the default SG and
# explicitly set its rules to empty.
# -----------------------------------------------------------------------------
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  # No ingress, no egress. Anything that needs traffic must use a purpose-
  # built SG; downstream modules (eks, rds, dns-tls) provide their own.
  ingress = []
  egress  = []

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-sg-stripped"
  })
}
