# =============================================================================
# Input variables for the VPC module.
# =============================================================================

variable "project_name" {
  description = "Short identifier used as a prefix on every VPC-scoped resource name."
  type        = string
  default     = "payeye"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 chars, lowercase letters, digits, and hyphens only."
  }
}

variable "env" {
  description = "Target environment name (e.g. 'dev', 'staging', 'prod'). Drives sizing, retention, and HA defaults at the composition layer."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "shared"], var.env)
    error_message = "env must be one of: dev, staging, prod, shared."
  }
}

variable "cidr_block" {
  description = "Primary CIDR block of the VPC. Must be a /16 to /20. Default carves space for 256 /24 subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "List of AWS availability zones to spread subnets across. Length determines fan-out for public, private-app, and private-db tiers. Must be >= 2 for any production-grade posture."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "azs must contain at least 2 AZs (HA minimum) and at most 3 (CIDR plan limit)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets. One per AZ, in the same order as var.azs. Hosts NAT GWs, ALBs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the private application subnets. One per AZ. Hosts EKS nodes and internal load balancers."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for the private database subnets. One per AZ. Hosts Aurora, ElastiCache. No 0.0.0.0/0 route."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "enable_nat_gateway" {
  description = "If true, provision NAT Gateways so private subnets can reach the internet for egress (package mirrors, AWS APIs over public endpoints, etc.)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Cost-vs-availability switch. If true, provision ONE NAT GW shared by all private subnets (cheaper, single AZ failure removes egress for the whole VPC). If false, one NAT GW per AZ. Should be false in prod."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "If true, enable VPC Flow Logs to CloudWatch Logs. Required for PCI-DSS and DORA forensics windows; should be true everywhere."
  type        = bool
  default     = true
}

variable "flow_log_traffic_type" {
  description = "Which packets to capture in flow logs. ALL gives full forensics; REJECT drops accepted packets to save volume; ACCEPT does the inverse."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be one of: ALL, ACCEPT, REJECT."
  }
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC Flow Logs. 30 is fine in dev, 365+ in prod (PCI-DSS expects 1 year online)."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a value supported by CloudWatch Logs (e.g., 30, 90, 365, 2557)."
  }
}

variable "flow_log_kms_key_arn" {
  description = "Optional KMS CMK ARN for encrypting the Flow Logs CloudWatch log group. If null, AWS-managed encryption is used."
  type        = string
  default     = null
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource on top of the module's own common tags."
  type        = map(string)
  default     = {}
}
