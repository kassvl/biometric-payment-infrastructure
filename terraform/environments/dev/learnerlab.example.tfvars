# =============================================================================
# AWS Academy Learner Lab tfvars
#
# Copy this to learnerlab.tfvars (gitignored) and fill in the AWS Account ID
# of YOUR lab session in the role ARNs. Apply with:
#
#   terraform apply -var-file=learnerlab.tfvars
#
# Key differences from the default dev composition:
#   - region: us-east-1 (Learner Lab default and usually the only allowed)
#   - EKS uses pre-existing LabRole for cluster + node IAM (Lab blocks iam:CreateRole)
#   - EBS CSI IRSA disabled (would require iam:CreateRole to provision)
#   - IAM password policy + EBS default encryption disabled (account singletons,
#     normally blocked or undesired in a shared lab account)
#   - WAF kept on (cheap; demonstrates the control)
#   - VPC endpoints kept off (cost; lab credit is finite)
#   - Single shared NAT Gateway (cost)
# =============================================================================

# Look up your Lab account ID with: aws sts get-caller-identity --query Account --output text
# Then replace 339713122678 below with your value.

project_name = "payeye"
env          = "dev"
region       = "us-east-1"

vpc_cidr_block = "10.0.0.0/16"

azs = [
  "us-east-1a",
  "us-east-1b",
]

public_subnet_cidrs      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs  = ["10.0.20.0/24", "10.0.21.0/24"]

# ----- Cost switches -----
single_nat_gateway   = true
enable_vpc_endpoints = false

# ----- Account singletons OFF (Learner Lab usually blocks them) -----
enable_iam_password_policy    = false
enable_default_ebs_encryption = false

# ----- Retention / WAF tuning -----
flow_log_retention_days = 7     # short in lab — credits are finite
enable_flow_logs        = false # Lab blocks iam:CreateRole for the flow-logs service role
waf_rate_limit_per_5min = 10000

# ----- EKS — Learner Lab specific -----
cluster_version                      = "1.30"
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

# REPLACE 339713122678 WITH YOUR LAB'S AWS ACCOUNT ID.
eks_cluster_iam_role_arn = "arn:aws:iam::339713122678:role/LabRole"
eks_node_iam_role_arn    = "arn:aws:iam::339713122678:role/LabRole"

# OIDC provider creation is usually permitted in Learner Lab. Flip to false
# if you get an iam:CreateOpenIDConnectProvider AccessDenied error.
eks_enable_irsa_oidc_provider = true

# EBS CSI IRSA requires iam:CreateRole — blocked in Lab. The addon falls
# back to the node IAM role (LabRole) for EBS API access — that works
# because LabRole has wide EBS permissions.
eks_enable_ebs_csi_irsa = false

# Single small node group — ON_DEMAND so the demo scales out reliably; SPOT
# is harder to capacity-plan against the lab's quotas.
node_groups = {
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

extra_tags = {
  Environment = "lab"
  OwnedBy     = "academy-learner-lab"
}
