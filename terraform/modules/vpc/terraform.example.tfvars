# =============================================================================
# Example tfvars showing a typical dev override of the VPC module.
# Copy to terraform.tfvars (gitignored) when iterating locally.
# =============================================================================

project_name = "biopay"
env          = "dev"

cidr_block = "10.0.0.0/16"

azs = [
  "eu-central-1a",
  "eu-central-1b",
]

public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

# Cost-optimized for dev: one shared NAT Gateway. Set to false in prod.
enable_nat_gateway = true
single_nat_gateway = true

enable_flow_logs        = true
flow_log_traffic_type   = "ALL"
flow_log_retention_days = 30

# extra_tags = {
#   "OnCallTeam" = "platform"
# }
