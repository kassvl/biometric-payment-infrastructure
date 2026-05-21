# =============================================================================
# Outputs re-exported from the dev composition.
#
# Convention: prefix module outputs with their domain so consumers know where
# they came from. Anything sensitive (e.g., raw account IDs, KMS key material)
# is not exported even when the underlying module emits it.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs in AZ order."
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private-app subnet IDs in AZ order (EKS workers go here)."
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private-db subnet IDs in AZ order (Aurora, ElastiCache)."
  value       = module.vpc.private_db_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IPs assigned to the NAT Gateway(s). Single entry in dev (single_nat_gateway=true)."
  value       = module.vpc.nat_gateway_public_ips
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group receiving VPC Flow Logs."
  value       = module.vpc.flow_log_group_name
}

# -----------------------------------------------------------------------------
# Security — KMS
# -----------------------------------------------------------------------------
output "kms_key_arns" {
  description = "Map of CMK domain (logs|secrets|rds|ebs) -> KMS key ARN. Consume from downstream modules with module.security.kms_key_arns[\"<domain>\"]."
  value       = module.security.kms_key_arns
}

output "kms_key_aliases" {
  description = "Map of CMK domain -> alias name. Aliases survive key replacement; prefer them in resource configurations."
  value       = module.security.kms_key_aliases
}

# -----------------------------------------------------------------------------
# Security — WAF
# -----------------------------------------------------------------------------
output "waf_web_acl_arn" {
  description = "ARN of the regional WAF v2 WebACL. Associate with the ALB once it exists."
  value       = module.security.waf_web_acl_arn
}

output "waf_log_group_name" {
  description = "Name of the CloudWatch log group receiving WAF logs."
  value       = module.security.waf_log_group_name
}

# -----------------------------------------------------------------------------
# Security — VPC endpoints (only populated when enable_vpc_endpoints = true)
# -----------------------------------------------------------------------------
output "gateway_vpc_endpoint_ids" {
  description = "Map of service -> gateway VPC endpoint ID. Empty in dev unless enable_vpc_endpoints=true."
  value       = module.security.gateway_vpc_endpoint_ids
}

output "interface_vpc_endpoint_ids" {
  description = "Map of service -> interface VPC endpoint ID. Empty in dev unless enable_vpc_endpoints=true."
  value       = module.security.interface_vpc_endpoint_ids
}

# -----------------------------------------------------------------------------
# Diagnostic
# -----------------------------------------------------------------------------
output "managing_account_singletons" {
  description = "Account-singleton resources this environment is managing. Useful when auditing which env owns each singleton across a multi-env account."
  value = {
    iam_password_policy    = module.security.iam_password_policy_managed
    default_ebs_encryption = module.security.default_ebs_encryption_managed
  }
}
