# =============================================================================
# Input variables for the security module.
# =============================================================================

# -----------------------------------------------------------------------------
# Naming and tagging
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Short identifier used as a prefix on every security-scoped resource name."
  type        = string
  default     = "payeye"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "env" {
  description = "Target environment name (dev, staging, prod, shared)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "shared"], var.env)
    error_message = "env must be one of: dev, staging, prod, shared."
  }
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource on top of the module's own common tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# VPC inputs (required when enable_vpc_endpoints = true)
#
# All VPC-derived inputs are nullable so the module can be used in an
# account-baseline-only mode (KMS + IAM + EBS) without a VPC at all.
# -----------------------------------------------------------------------------
variable "vpc_id" {
  description = "ID of the VPC where interface and gateway endpoints will be created. Required when enable_vpc_endpoints is true."
  type        = string
  default     = null
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC. Used by the interface-endpoint security group to allow 443 ingress from inside the VPC only. Required when enable_vpc_endpoints is true."
  type        = string
  default     = null
}

variable "private_app_subnet_ids" {
  description = "Private-app subnet IDs where interface VPC endpoint ENIs will be placed (one per AZ). Required when enable_vpc_endpoints is true."
  type        = list(string)
  default     = []
}

variable "private_app_route_table_ids" {
  description = "Private-app route table IDs that gateway VPC endpoints will be associated to. Required when enable_vpc_endpoints is true."
  type        = list(string)
  default     = []
}

variable "private_db_route_table_ids" {
  description = "Private-db route table IDs that gateway VPC endpoints will also be associated to. Required when enable_vpc_endpoints is true and the data tier should reach S3/DynamoDB without leaving the VPC."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------
variable "kms_key_deletion_window_in_days" {
  description = "Days to wait before a KMS key is permanently deleted after destroy. AWS supports 7-30; 30 is the safe default for production keys."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}

variable "kms_keys_to_create" {
  description = "Set of CMK domains to create. Each becomes an alias 'alias/<project>-<env>-<name>' with a service-scoped key policy. Defaults: logs (CloudWatch), secrets (Secrets Manager), rds (Aurora storage), ebs (EBS volumes)."
  type        = set(string)
  default     = ["logs", "secrets", "rds", "ebs"]

  validation {
    condition     = length(var.kms_keys_to_create) > 0
    error_message = "kms_keys_to_create must contain at least one key domain."
  }
}

# -----------------------------------------------------------------------------
# VPC endpoints
# -----------------------------------------------------------------------------
variable "enable_vpc_endpoints" {
  description = "If true, provision the configured set of gateway and interface VPC endpoints. Strongly recommended in prod to keep AWS API traffic on the AWS backbone instead of NAT."
  type        = bool
  default     = true
}

variable "interface_vpc_endpoints" {
  description = "Set of AWS service short-names for which to create interface VPC endpoints (one ENI per AZ). 'kms' is required for VPC-private SSE-KMS and IAM-IDP token decryption flows."
  type        = set(string)
  default = [
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
}

variable "gateway_vpc_endpoints" {
  description = "Set of AWS service short-names for which to create gateway VPC endpoints. Only s3 and dynamodb are supported by AWS as gateway endpoints."
  type        = set(string)
  default     = ["s3", "dynamodb"]

  validation {
    condition     = alltrue([for s in var.gateway_vpc_endpoints : contains(["s3", "dynamodb"], s)])
    error_message = "Only 's3' and 'dynamodb' are supported as gateway VPC endpoints. All others must use interface endpoints."
  }
}

# -----------------------------------------------------------------------------
# AWS WAF v2 (regional)
# -----------------------------------------------------------------------------
variable "enable_waf" {
  description = "If true, create a regional AWS WAF v2 WebACL. The ALB-association is performed at the env composition layer once the ALB exists."
  type        = bool
  default     = true
}

variable "waf_log_retention_days" {
  description = "CloudWatch retention for WAF logs. 30 in dev; 365+ in prod for FinTech audit trails."
  type        = number
  default     = 30
}

variable "waf_rate_limit_per_5min" {
  description = "Per-IP request count over 5-minute windows above which the rate-limit rule blocks the source IP. 10000 is a moderate baseline; tune lower for auth endpoints."
  type        = number
  default     = 10000

  validation {
    condition     = var.waf_rate_limit_per_5min >= 100 && var.waf_rate_limit_per_5min <= 2000000000
    error_message = "waf_rate_limit_per_5min must be between 100 and 2,000,000,000 (AWS WAF v2 limits)."
  }
}

# -----------------------------------------------------------------------------
# IAM account password policy
#
# These resources are ACCOUNT-WIDE singletons. Only one terraform-managed
# password policy can exist per AWS account. If multiple environments call
# this module against the same account, set enable_iam_password_policy=true
# in exactly one of them (typically prod, or a dedicated account-baseline env).
# -----------------------------------------------------------------------------
variable "enable_iam_password_policy" {
  description = "If true, manage the AWS account password policy. Account-wide singleton; enable in only ONE module instance per AWS account."
  type        = bool
  default     = true
}

variable "password_min_length" {
  description = "Minimum IAM user password length. PCI-DSS 8.3.6 requires at least 12; 14 gives a margin."
  type        = number
  default     = 14

  validation {
    condition     = var.password_min_length >= 12 && var.password_min_length <= 128
    error_message = "password_min_length must be between 12 (PCI-DSS minimum) and 128."
  }
}

variable "password_max_age" {
  description = "Days after which IAM users must rotate their password. 90 aligns with PCI-DSS 8.6.3."
  type        = number
  default     = 90
}

variable "password_reuse_prevention" {
  description = "Number of previous passwords IAM remembers and disallows reuse of."
  type        = number
  default     = 24
}

# -----------------------------------------------------------------------------
# EBS default encryption (account-wide singleton)
# -----------------------------------------------------------------------------
variable "enable_default_ebs_encryption" {
  description = "If true, enable account-region-wide default EBS encryption and set the default KMS key to the EBS CMK created by this module. Account-region-wide singleton; enable in only ONE module instance per AWS account+region."
  type        = bool
  default     = true
}
