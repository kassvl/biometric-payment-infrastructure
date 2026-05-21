# =============================================================================
# Example tfvars for the EKS module.
#
# Copy to terraform.tfvars (gitignored) when iterating standalone. In normal
# use, the environment composition supplies these values.
# =============================================================================

project_name = "payeye"
env          = "dev"

cluster_version = "1.30"

# ----- VPC wiring (fed from module.vpc.* outputs in env composition) ---------
# vpc_id                   = "vpc-..."
# control_plane_subnet_ids = ["subnet-...", "subnet-..."]
# node_subnet_ids          = null  # defaults to control_plane_subnet_ids

# ----- Endpoint access -------------------------------------------------------
# Private endpoint ON, public endpoint ON for kubectl from the operator
# laptop. Tighten public_access_cidrs in prod to office + on-call CIDRs.
cluster_endpoint_private_access      = true
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

# ----- Encryption ------------------------------------------------------------
# In dev we leave secrets envelope encryption off (etcd is still encrypted
# with AWS-managed keys). For prod, set this to security.kms_key_arns["..."]
# of an EKS-dedicated CMK (we don't reuse the rds/secrets/logs CMKs).
# cluster_encryption_kms_key_arn = null

# Node EBS root volumes. When null, EKS uses the AWS account default EBS
# encryption key (set via the security module's ebs CMK).
# node_disk_kms_key_arn = null

# ----- Logging --------------------------------------------------------------
cluster_log_types          = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
cluster_log_retention_days = 30

# ----- Node groups ----------------------------------------------------------
# Two-group example: a small system on-demand group + a SPOT app group.
node_groups = {
  system = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    ami_type       = "AL2_x86_64"
    disk_size_gib  = 30
    desired_size   = 2
    min_size       = 2
    max_size       = 4
    labels = {
      "workload-class" = "system"
    }
    taints = [
      {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      },
    ]
  }

  app = {
    instance_types = ["t3.large", "t3a.large"]
    capacity_type  = "SPOT"
    ami_type       = "AL2_x86_64"
    disk_size_gib  = 50
    desired_size   = 0
    min_size       = 0
    max_size       = 6
    labels = {
      "workload-class" = "app"
    }
    taints = []
  }
}

# ----- Addons (defaults are normally fine) ----------------------------------
# addons = {
#   "vpc-cni"           = {}
#   "coredns"           = {}
#   "kube-proxy"        = {}
#   "aws-ebs-csi-driver" = {}
# }

extra_tags = {
  OnCallTeam = "platform"
}
