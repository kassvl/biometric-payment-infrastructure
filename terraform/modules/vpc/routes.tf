# =============================================================================
# Route tables and route table associations.
#
#  - One public route table for the whole VPC. 0.0.0.0/0 → IGW.
#  - One private-app route table PER AZ. 0.0.0.0/0 → AZ-local NAT GW.
#    (Per-AZ tables prevent cross-AZ NAT data processing fees and keep
#     egress fault-isolated.)
#  - One private-db route table PER AZ. NO 0.0.0.0/0 route at all.
# =============================================================================


# -----------------------------------------------------------------------------
# Public route table
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-public"
    Tier = "public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}


# -----------------------------------------------------------------------------
# Private-app route tables (one per AZ).
# Each AZ's RT routes 0.0.0.0/0 to the NAT GW in the SAME AZ when in HA mode.
# In single-NAT mode, all private-app RTs share the single NAT GW.
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_app" {
  for_each = local.private_app_subnets_by_az

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-private-app-${each.key}"
    Tier = "private-app"
  })
}

resource "aws_route" "private_app_egress" {
  # Only emit a route if NAT GW is enabled. Otherwise the private-app subnets
  # have no internet egress at all (which is also a valid posture).
  for_each = var.enable_nat_gateway ? local.private_app_subnets_by_az : {}

  route_table_id         = aws_route_table.private_app[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  # In HA mode pick the AZ-local NAT; in single-NAT mode pick the only NAT
  # we created (in the first AZ).
  nat_gateway_id = (
    var.single_nat_gateway
    ? aws_nat_gateway.main[var.azs[0]].id
    : aws_nat_gateway.main[each.key].id
  )
}

resource "aws_route_table_association" "private_app" {
  for_each = aws_subnet.private_app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app[each.key].id
}


# -----------------------------------------------------------------------------
# Private-db route tables (one per AZ). No 0.0.0.0/0 route. Local VPC traffic
# only. Reaches AWS APIs (KMS, Secrets Manager) via VPC endpoints, not NAT.
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_db" {
  for_each = local.private_db_subnets_by_az

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt-private-db-${each.key}"
    Tier = "private-db"
  })
}

resource "aws_route_table_association" "private_db" {
  for_each = aws_subnet.private_db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db[each.key].id
}
