# =============================================================================
# Example tfvars for the security module.
# Copy to terraform.tfvars (gitignored) when iterating standalone.
# In normal use, the environment composition supplies these values.
# =============================================================================

project_name = "payeye"
env          = "dev"

# ----- VPC inputs (fed from module.vpc.* outputs in the env composition) -----
# vpc_id                    = "vpc-..."
# vpc_cidr_block            = "10.0.0.0/16"
# private_app_subnet_ids    = ["subnet-...", "subnet-..."]
# private_app_route_table_ids = ["rtb-...", "rtb-..."]
# private_db_route_table_ids  = ["rtb-...", "rtb-..."]

# ----- KMS -----
kms_key_deletion_window_in_days = 30
kms_keys_to_create              = ["logs", "secrets", "rds", "ebs"]

# ----- VPC endpoints -----
enable_vpc_endpoints = true
interface_vpc_endpoints = [
  "kms",
  "secretsmanager",
  "ecr.api",
  "ecr.dkr",
  "eks",
  "sts",
  "ec2",
  "logs",
  "ssm",
  "monitoring",
]
gateway_vpc_endpoints = ["s3", "dynamodb"]

# ----- WAF -----
enable_waf              = true
waf_log_retention_days  = 30
waf_rate_limit_per_5min = 10000

# ----- IAM password policy (account singleton — keep true in only ONE env) ---
enable_iam_password_policy = true
password_min_length        = 14
password_max_age           = 90
password_reuse_prevention  = 24

# ----- EBS default encryption (account+region singleton) --------------------
enable_default_ebs_encryption = true

# extra_tags = {
#   "OnCallTeam" = "platform"
# }
