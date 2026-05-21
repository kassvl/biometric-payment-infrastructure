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

variable "enable_flow_logs" {
  description = "If true, enable VPC Flow Logs to CloudWatch. Requires iam:CreateRole — set false in restricted environments (e.g., AWS Academy Learner Lab) where role creation is blocked."
  type        = bool
  default     = true
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

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------
variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the EKS public API endpoint. 0.0.0.0/0 is fine for dev portfolio demos but tighten to operator + on-call ranges in prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = "Map of EKS managed node group definitions. Default ships ONE small ON_DEMAND group sized for a portfolio demo (~$0.083/hour for 2 t3.medium)."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    ami_type       = string
    disk_size_gib  = number
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))

  default = {
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      ami_type       = "AL2_x86_64"
      disk_size_gib  = 30
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      labels         = { "workload-class" = "system" }
      taints         = []
    }
  }
}

# -----------------------------------------------------------------------------
# Learner Lab / restricted-IAM environment toggles
#
# Set these in a learnerlab.tfvars file (gitignored) when applying inside an
# AWS Academy Learner Lab. Defaults are tuned for an unrestricted account.
# -----------------------------------------------------------------------------
variable "eks_cluster_iam_role_arn" {
  description = "Pre-existing IAM role ARN to use as the EKS cluster role. Set to LabRole's ARN in AWS Academy Learner Lab. Null = module creates the role itself."
  type        = string
  default     = null
}

variable "eks_node_iam_role_arn" {
  description = "Pre-existing IAM role ARN to use as the EKS node instance role. Set to LabRole's ARN in AWS Academy Learner Lab. Null = module creates the role itself."
  type        = string
  default     = null
}

variable "eks_enable_irsa_oidc_provider" {
  description = "If true (default), create the IAM OIDC provider for IRSA. Set to false if your lab type blocks iam:CreateOpenIDConnectProvider."
  type        = bool
  default     = true
}

variable "eks_enable_ebs_csi_irsa" {
  description = "If true (default), create a dedicated IRSA role for the aws-ebs-csi-driver. Set to false in Learner Lab — the addon falls back to the node IAM role (LabRole) for EBS access."
  type        = bool
  default     = true
}
