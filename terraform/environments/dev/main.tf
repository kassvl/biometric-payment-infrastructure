# =============================================================================
# dev environment composition.
#
# Wires the reusable modules together. Order is important for HUMAN reading
# (it matches the dependency DAG); Terraform itself plans the actual order.
#
# Cycle note: the VPC module accepts an optional KMS key ARN for Flow Log
# encryption (`flow_log_kms_key_arn`). Wiring `module.security.kms_key_arns["logs"]`
# into it would create a vpc <-> security module-level cycle (security needs
# vpc_id, vpc would need security's KMS). For dev we leave Flow Logs encrypted
# with AWS-managed encryption — still encrypted, just not under our CMK.
# Prod will introduce a separate root `kms` module that both vpc and security
# depend on, breaking the cycle cleanly.
# =============================================================================

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  env          = var.env

  cidr_block               = var.vpc_cidr_block
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_flow_logs        = true
  flow_log_traffic_type   = "ALL"
  flow_log_retention_days = var.flow_log_retention_days

  # See cycle note in the file header. Flow logs use AWS-managed encryption
  # in dev. Set this to module.security.kms_key_arns["logs"] in a future
  # prod composition that breaks the cycle via a separate kms module.
  flow_log_kms_key_arn = null

  extra_tags = var.extra_tags
}

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  env          = var.env

  # VPC wiring — only meaningful when enable_vpc_endpoints is true, but we
  # pass them anyway to document the contract and keep the diff readable
  # if a later operator flips the flag.
  vpc_id                      = module.vpc.vpc_id
  vpc_cidr_block              = module.vpc.vpc_cidr_block
  private_app_subnet_ids      = module.vpc.private_app_subnet_ids
  private_app_route_table_ids = module.vpc.private_app_route_table_ids
  private_db_route_table_ids  = module.vpc.private_db_route_table_ids

  # KMS — keep the full set; aliases scope to <project>-<env> so dev keys
  # do not collide with a future prod composition in the same account.
  kms_keys_to_create              = ["logs", "secrets", "rds", "ebs"]
  kms_key_deletion_window_in_days = 30

  # VPC endpoints — disabled by default in dev for cost (see variables.tf).
  enable_vpc_endpoints = var.enable_vpc_endpoints

  # WAF — created here; ALB association happens once an ALB exists
  # (downstream of EKS / Ingress controller wiring).
  enable_waf              = true
  waf_log_retention_days  = var.flow_log_retention_days
  waf_rate_limit_per_5min = var.waf_rate_limit_per_5min

  # Account-level singletons. In a single-account portfolio repo, dev IS the
  # only environment, so it owns the singletons. The moment a prod env is
  # added in the same account, flip these to false here and true in prod.
  enable_iam_password_policy    = var.enable_iam_password_policy
  enable_default_ebs_encryption = var.enable_default_ebs_encryption

  password_min_length       = 14
  password_max_age          = 90
  password_reuse_prevention = 24

  extra_tags = var.extra_tags
}


# =============================================================================
# EKS module — depends on VPC for subnets and on security for KMS keys.
#
# In dev the cluster is small (one node group, 2x t3.medium ON_DEMAND).
# Cluster secrets envelope encryption is OFF (etcd is still encrypted at the
# storage layer with AWS-managed keys); turn it on in prod by passing a
# dedicated cluster-secrets CMK. Node EBS volumes use the security module's
# 'ebs' CMK; control-plane logs use the 'logs' CMK.
# =============================================================================

module "eks" {
  source = "../../modules/eks"

  project_name = var.project_name
  env          = var.env

  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  control_plane_subnet_ids = module.vpc.private_app_subnet_ids
  node_subnet_ids          = module.vpc.private_app_subnet_ids

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Encryption wiring. Note: cluster_encryption_kms_key_arn intentionally null
  # in dev (one less moving piece for the demo). For prod, create an
  # eks-secrets CMK in the security module and pass it here.
  cluster_encryption_kms_key_arn = null
  node_disk_kms_key_arn          = module.security.kms_key_arns["ebs"]
  cluster_log_kms_key_arn        = module.security.kms_key_arns["logs"]

  cluster_log_retention_days = var.flow_log_retention_days

  node_groups = var.node_groups

  # Restricted-IAM environment passthrough (default null/true = unrestricted
  # account; set in learnerlab.tfvars for AWS Academy Learner Lab).
  cluster_iam_role_arn      = var.eks_cluster_iam_role_arn
  node_iam_role_arn         = var.eks_node_iam_role_arn
  enable_irsa_oidc_provider = var.eks_enable_irsa_oidc_provider
  enable_ebs_csi_irsa       = var.eks_enable_ebs_csi_irsa

  extra_tags = var.extra_tags
}
