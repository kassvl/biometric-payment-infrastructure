# =============================================================================
# Input variables for the dev environment composition.
#
# Defaults are tuned for COST: single shared NAT, no VPC endpoints, AWS-managed
# encryption on flow logs (avoids a vpc <-> security module cycle in the dev
# composition). Account-level singletons (IAM password policy, EBS default
# encryption) ARE enabled here because dev is the only env in this account.
# =============================================================================

variable "project_name" {
  description = "Short identifier propagated through every module."
  type        = string
  default     = "payeye"
}

variable "env" {
  description = "Environment name. Drives state key, tags, and module-level conventions."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-central-1"
}

# -----------------------------------------------------------------------------
# VPC inputs
# -----------------------------------------------------------------------------
variable "vpc_cidr_block" {
  description = "Primary VPC CIDR. /16 leaves room for ~250 EKS nodes per AZ at default pod density."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "AWS availability zones the subnets are spread across."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private-app subnet CIDRs (EKS workers, internal LBs)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "Private-db subnet CIDRs (Aurora, ElastiCache; no internet route)."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# -----------------------------------------------------------------------------
# Cost / posture switches
# -----------------------------------------------------------------------------
variable "single_nat_gateway" {
  description = "If true (DEV DEFAULT), provision ONE shared NAT Gateway instead of one-per-AZ. Saves ~$32/month per extra AZ at the cost of single-AZ-failure egress impact."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "If true, provision the configured set of gateway and interface VPC endpoints. DEV DEFAULT IS FALSE: 10 interface endpoints x 2 AZs = 20 ENIs which is roughly $144/month full-time and dwarfs every other dev cost. Flip to true in prod."
  type        = bool
  default     = false
}

variable "enable_iam_password_policy" {
  description = "Account-wide singleton. In a single-account portfolio repo where dev is the only environment, set true here. Set false here and true in prod when you add a second env."
  type        = bool
  default     = true
}

variable "enable_default_ebs_encryption" {
  description = "Account+region singleton. Free, and forces every new EBS volume to be encrypted with our 'ebs' CMK by default. Same singleton rule as the password policy."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC Flow Logs. 30 days for dev; raise to 365+ in prod."
  type        = number
  default     = 30
}

variable "waf_rate_limit_per_5min" {
  description = "WAF per-IP rate limit (block above this many requests in any 5-minute window). 10000 is generous for dev; tune lower for prod auth endpoints."
  type        = number
  default     = 10000
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource on top of provider default_tags and module common tags."
  type        = map(string)
  default = {
    OnCallTeam = "platform"
  }
}
