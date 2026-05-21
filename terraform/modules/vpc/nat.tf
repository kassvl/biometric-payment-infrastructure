# =============================================================================
# NAT Gateways — outbound internet access for private subnets.
#
# Two modes:
#   - single_nat_gateway = false (default for prod): one NAT GW per AZ. If
#     one AZ goes down, the other AZ keeps egress alive. No cross-AZ data
#     processing fees. ~$32/month per NAT + per-GB processing.
#   - single_nat_gateway = true (dev): one NAT GW total. Cheap, but a single
#     AZ failure removes egress for the whole VPC. Acceptable for dev only.
#
# EIPs are allocated separately so a NAT GW can be replaced (e.g., in a
# blue/green region migration) without re-IPing the entire egress address.
# =============================================================================

resource "aws_eip" "nat" {
  for_each = local.nat_gateways_by_az

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
    Tier = "public"
  })

  # Internet Gateway must exist before an EIP can be associated with a NAT GW.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  for_each = local.nat_gateways_by_az

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  # Connectivity type "public" gives outbound internet via the EIP.
  connectivity_type = "public"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${each.key}"
    Tier = "public"
  })

  # Public subnet route to IGW must exist before the NAT GW is functional;
  # the NAT GW resource doesn't strictly require it for creation, but
  # listing the dependency is good documentation.
  depends_on = [
    aws_internet_gateway.main,
    aws_subnet.public,
  ]
}
