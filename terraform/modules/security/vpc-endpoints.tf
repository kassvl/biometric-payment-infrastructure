# =============================================================================
# VPC Endpoints — Gateway and Interface.
#
# Gateway endpoints (S3, DynamoDB):
#   - Free.
#   - Attach to route tables (no ENIs, no IPs).
#   - Traffic to the service stays on the AWS backbone instead of egressing
#     via NAT Gateway. Cuts NAT data-processing fees and removes a public
#     path for AWS API traffic.
#
# Interface endpoints (KMS, Secrets Manager, ECR, EKS, STS, EC2, CW Logs,
# SSM, CloudWatch monitoring):
#   - Charged per ENI per AZ + per-GB processing.
#   - Place an ENI in each private-app subnet (one per AZ).
#   - Private DNS makes the standard service hostname resolve to the
#     endpoint's private IP from inside the VPC, so application code does
#     not need to know about the endpoint.
#
# A purpose-built security group restricts ingress on 443 to the VPC CIDR
# only. That keeps the endpoint reachable from any pod or instance in the
# VPC while staying invisible to anything outside.
# =============================================================================


# -----------------------------------------------------------------------------
# Security group used by every interface endpoint.
# Egress is intentionally open: AWS endpoint ENIs need to talk back to the
# AWS service plane on the AWS backbone. Ingress is locked to 443 from the
# VPC CIDR — there is no other legitimate origin.
# -----------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name        = "${local.name_prefix}-vpc-endpoints"
  description = "Allow 443 from inside the VPC to AWS service interface endpoints."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  count = var.enable_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from anywhere inside the VPC."
  cidr_ipv4         = var.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_all" {
  count = var.enable_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "Allow ENIs to talk back to AWS service planes on the AWS backbone."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.common_tags
}


# -----------------------------------------------------------------------------
# Gateway endpoints (S3, DynamoDB).
#
# We attach gateway endpoints to BOTH the private-app and private-db route
# tables. The data tier needs S3 access (for backups, reading static config)
# without an internet route — gateway endpoints are exactly the mechanism
# AWS expects for that.
# -----------------------------------------------------------------------------
locals {
  # Combine private-app and private-db route tables for gateway endpoint
  # association. Filtered to the lists actually provided.
  gateway_route_table_ids = concat(
    var.private_app_route_table_ids,
    var.private_db_route_table_ids,
  )
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.enable_vpc_endpoints ? var.gateway_vpc_endpoints : []

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_route_table_ids

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-vpce-${replace(each.value, ".", "-")}"
    Service = each.value
  })
}


# -----------------------------------------------------------------------------
# Interface endpoints.
#
# Each interface endpoint creates one ENI per subnet listed. Private DNS is
# enabled so callers can keep using the public hostname (e.g.,
# "kms.eu-central-1.amazonaws.com") and DNS resolves to the private IP
# automatically.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_endpoints ? var.interface_vpc_endpoints : []

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_app_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-vpce-${replace(each.value, ".", "-")}"
    Service = each.value
  })
}
