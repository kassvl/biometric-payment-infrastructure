# =============================================================================
# Input variables for the EKS module.
# =============================================================================

# -----------------------------------------------------------------------------
# Naming and tagging
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "Short identifier used as a prefix on every EKS-scoped resource name."
  type        = string
  default     = "biopay"

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

variable "cluster_name_override" {
  description = "Optional full override for the EKS cluster name. If null, resolves to '<project>-<env>-eks'."
  type        = string
  default     = null
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Cluster shape
# -----------------------------------------------------------------------------
variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane. Pinned to 1.30 in this repo. Bump deliberately via an ADR + a separate PR; AWS deprecates a minor every ~12 months."
  type        = string
  default     = "1.30"

  validation {
    condition     = can(regex("^1\\.(2[5-9]|3[0-9])$", var.cluster_version))
    error_message = "cluster_version must look like 1.30 (1.25 through 1.39 are acceptable)."
  }
}

# -----------------------------------------------------------------------------
# VPC wiring (required)
# -----------------------------------------------------------------------------
variable "vpc_id" {
  description = "ID of the VPC the cluster lives in."
  type        = string
}

variable "control_plane_subnet_ids" {
  description = "Subnet IDs the EKS-managed control plane ENIs are placed in. Use private-app subnets for a private control-plane posture; AWS still attaches ENIs in each AZ. Minimum 2 subnets in 2 AZs."
  type        = list(string)

  validation {
    condition     = length(var.control_plane_subnet_ids) >= 2
    error_message = "control_plane_subnet_ids must contain at least 2 subnets in different AZs."
  }
}

variable "node_subnet_ids" {
  description = "Subnet IDs where managed node groups will launch worker nodes. Use private-app subnets. Defaults to control_plane_subnet_ids if null (typical for shared subnets)."
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Cluster endpoint access
#
# Best practice: private endpoint ON, public endpoint ON but CIDR-restricted to
# operator + on-call jumphost ranges only. Pure-private (public OFF) requires
# a VPN or DX into the VPC to run kubectl, which is heavy for dev.
# -----------------------------------------------------------------------------
variable "cluster_endpoint_private_access" {
  description = "If true, the cluster API server is reachable from inside the VPC at a private IP."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "If true, the cluster API server is reachable from the internet (subject to public_access_cidrs)."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Default ['0.0.0.0/0'] is fine for dev portfolio demos but must be tightened in prod."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------
variable "cluster_encryption_kms_key_arn" {
  description = "KMS CMK ARN for envelope encryption of Kubernetes secrets at rest in etcd. Strongly recommended in prod; null disables CMK encryption (etcd is still encrypted with AWS-managed keys)."
  type        = string
  default     = null
}

variable "node_disk_kms_key_arn" {
  description = "KMS CMK ARN for encrypting the EBS root volume on every worker node. Falls back to AWS account default EBS key (set via the security module) when null — that is normally fine."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Control-plane logging
# -----------------------------------------------------------------------------
variable "cluster_log_types" {
  description = "Which EKS control-plane log streams to enable. All five give complete forensics; api+audit are the minimum for any audited workload."
  type        = set(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition = alltrue([
      for t in var.cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "cluster_log_types entries must be in: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention for the EKS control-plane log group. 30 in dev; 365+ in prod for PCI-DSS audit windows."
  type        = number
  default     = 30
}

variable "cluster_log_kms_key_arn" {
  description = "Optional KMS CMK ARN for encrypting the EKS control-plane log group. Null leaves AWS-managed encryption in place."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Node groups
#
# Each entry in node_groups becomes one managed node group. The map key is
# the node-group identifier (used in tags and the node-group name).
# -----------------------------------------------------------------------------
variable "node_groups" {
  description = "Map of node-group-name -> configuration. Each value declares instance shape, scaling, and Kubernetes labels/taints. Keep at least one ON_DEMAND group for system workloads; SPOT is fine for stateless app workloads."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string # "ON_DEMAND" or "SPOT"
    ami_type       = string # e.g. "AL2_x86_64", "AL2_ARM_64", "BOTTLEROCKET_x86_64"
    disk_size_gib  = number
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE, NO_EXECUTE, PREFER_NO_SCHEDULE
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
# IAM — restricted-environment escape hatch
#
# By default the module creates its own cluster role, node role, and
# EBS CSI IRSA role. In environments where iam:CreateRole is blocked
# (e.g., AWS Academy Learner Lab, sandbox AWS Organizations with hardened
# SCPs), supply pre-existing role ARNs and the module will skip role
# creation and use them instead.
#
# Pre-existing roles MUST already trust the right service principal:
#   - cluster_iam_role_arn must trust eks.amazonaws.com
#   - node_iam_role_arn    must trust ec2.amazonaws.com
#
# AWS Academy Learner Lab provides a single 'LabRole' that already trusts
# both, plus most AWS service principals — passing the LabRole ARN to BOTH
# inputs is the canonical way to run this module in a Learner Lab.
# -----------------------------------------------------------------------------
variable "cluster_iam_role_arn" {
  description = "Pre-existing IAM role ARN to use as the EKS cluster role. If null, the module creates one. Required pre-existing trust policy: eks.amazonaws.com. Required attached policy: AmazonEKSClusterPolicy (LabRole has it bundled)."
  type        = string
  default     = null
}

variable "node_iam_role_arn" {
  description = "Pre-existing IAM role ARN to use as the EKS node instance role. If null, the module creates one. Required pre-existing trust policy: ec2.amazonaws.com. Required attached policies: AmazonEKSWorkerNodePolicy + AmazonEC2ContainerRegistryReadOnly + AmazonEKS_CNI_Policy (LabRole has them all)."
  type        = string
  default     = null
}

variable "enable_irsa_oidc_provider" {
  description = "If true (default), create the IAM OpenID Connect provider for IRSA. Some restricted environments block iam:CreateOpenIDConnectProvider; setting this to false produces a working cluster without IRSA — pods then use the node IAM role for AWS access (legacy pattern, less secure but functional)."
  type        = bool
  default     = true
}

variable "enable_ebs_csi_irsa" {
  description = "If true (default), create a dedicated IRSA role for the aws-ebs-csi-driver pod. Requires enable_irsa_oidc_provider=true AND iam:CreateRole permission. Set to false in restricted environments where iam:CreateRole is blocked — the addon will fall back to using the node IAM role for EBS API access, which works as long as the node role has AmazonEBSCSIDriverPolicy or equivalent permissions (LabRole does)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Addons (managed)
#
# Addon versions are intentionally NOT pinned in defaults. AWS maintains a
# matrix of compatible versions per Kubernetes minor version; leaving the
# version unset (null) lets EKS pick the recommended one for the cluster
# version, which is what we want for dev and most prod cases.
# -----------------------------------------------------------------------------
variable "addons" {
  description = "Map of EKS-managed addon configurations. Set version=null to use the recommended-for-cluster-version pin."
  type = map(object({
    version                     = optional(string)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    configuration_values        = optional(string)
    preserve                    = optional(bool, false)
  }))

  default = {
    "vpc-cni"            = {}
    "coredns"            = {}
    "kube-proxy"         = {}
    "aws-ebs-csi-driver" = {}
  }
}
