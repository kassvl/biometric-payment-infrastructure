# =============================================================================
# Example tfvars for the bootstrap module.
#
# Copy this file to `terraform.tfvars` (which is gitignored) and adjust if
# you need to override a default. Most projects only override `project_name`
# and `region`.
# =============================================================================

# Short identifier used as a prefix on every bootstrap resource.
# project_name = "payeye"

# Primary AWS region.
# region = "eu-central-1"

# DynamoDB lock table name. Default works for most projects.
# dynamodb_table_name = "payeye-tfstate-locks"

# KMS alias for the state-encryption CMK. Must start with `alias/`.
# kms_alias = "alias/payeye-tfstate"

# Number of days to retain noncurrent state versions. Default 365.
# noncurrent_version_expiration_days = 365

# Number of days to retain access logs. Default 2557 (~7 years).
# log_retention_days = 2557

# Allow `terraform destroy` to wipe non-empty buckets. NEVER true in prod.
# force_destroy = false

# Extra tags merged onto every resource.
# extra_tags = {
#   "BusinessUnit" = "FinTech"
#   "OnCallTeam"   = "platform"
# }
