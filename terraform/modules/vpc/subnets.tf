# =============================================================================
# Subnets — three tiers across N AZs.
#
# Three-tier segmentation maps onto a PCI-DSS trust boundary:
#
#   Internet ─► Public ─► Private-app ─► Private-db
#                ▲           ▲              ▲
#                │           │              └── No 0.0.0.0/0 route at all.
#                │           └── Outbound only via per-AZ NAT GW.
#                └── Only resources allowed to face the internet (ALB, NAT).
#
# Subnets use for_each over a map keyed by AZ for stable resource addresses.
# =============================================================================


# -----------------------------------------------------------------------------
# Public subnets — host ALBs and NAT Gateways.
# map_public_ip_on_launch is intentionally false: instances launched here
# get a public IP only when a downstream module asks for one explicitly.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets_by_az

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                             = "${local.name_prefix}-public-${each.key}"
    Tier                                             = "public"
    "kubernetes.io/role/elb"                         = "1"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  })
}

# -----------------------------------------------------------------------------
# Private-app subnets — host EKS worker nodes and internal load balancers.
# Tagged for the EKS load-balancer controller so it can place internal NLBs/ALBs.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private_app" {
  for_each = local.private_app_subnets_by_az

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                             = "${local.name_prefix}-private-app-${each.key}"
    Tier                                             = "private-app"
    "kubernetes.io/role/internal-elb"                = "1"
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
  })
}

# -----------------------------------------------------------------------------
# Private-db subnets — host Aurora and ElastiCache. NO 0.0.0.0/0 route at all
# (set later in routes.tf): the data tier never needs general internet egress.
# Required AWS endpoints (KMS, Secrets Manager) reach the DB tier via VPC
# endpoints (configured in the security/dns-tls modules, not here).
# -----------------------------------------------------------------------------
resource "aws_subnet" "private_db" {
  for_each = local.private_db_subnets_by_az

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-db-${each.key}"
    Tier = "private-db"
  })
}
