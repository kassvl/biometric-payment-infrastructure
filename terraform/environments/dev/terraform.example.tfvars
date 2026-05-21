# =============================================================================
# Example tfvars for the dev environment.
#
# Copy to terraform.tfvars (gitignored) only if you need to override a
# default. The defaults are tuned for a single-account portfolio repo where
# dev is the ONLY environment in the account.
# =============================================================================

# project_name = "payeye"
# env          = "dev"
# region       = "eu-central-1"

# ----- VPC sizing (defaults are typically fine) -----
# vpc_cidr_block = "10.0.0.0/16"
# azs            = ["eu-central-1a", "eu-central-1b"]
# public_subnet_cidrs      = ["10.0.1.0/24",  "10.0.2.0/24"]
# private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
# private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

# ----- Cost switches -----
# Single shared NAT Gateway (saves ~$32/mo vs HA NAT). DEV DEFAULT = true.
# single_nat_gateway = true
#
# Provision interface VPC endpoints (10 services). Roughly $144/month full-time
# for the interface endpoints alone — DEV DEFAULT = false.
# enable_vpc_endpoints = false

# ----- Account singletons (dev is the only env in this portfolio account) ---
# enable_iam_password_policy    = true
# enable_default_ebs_encryption = true

# ----- Retention / WAF tuning -----
# flow_log_retention_days = 30
# waf_rate_limit_per_5min = 10000

# ----- Tags -----
# extra_tags = {
#   OnCallTeam = "platform"
#   CostCenter = "platform"
# }
