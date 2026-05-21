# =============================================================================
# Outputs consumed by composing environments and downstream modules.
# =============================================================================


# -----------------------------------------------------------------------------
# KMS — emitted as maps so callers can reference by name.
# -----------------------------------------------------------------------------
output "kms_key_arns" {
  description = "Map of CMK domain name (logs|secrets|rds|ebs|...) → KMS key ARN."
  value       = { for name, key in aws_kms_key.this : name => key.arn }
}

output "kms_key_ids" {
  description = "Map of CMK domain name → raw KMS key ID."
  value       = { for name, key in aws_kms_key.this : name => key.key_id }
}

output "kms_key_aliases" {
  description = "Map of CMK domain name → alias name (alias/...). Preferred over raw IDs because aliases survive key replacement."
  value       = { for name, alias in aws_kms_alias.this : name => alias.name }
}


# -----------------------------------------------------------------------------
# VPC endpoints
# -----------------------------------------------------------------------------
output "vpc_endpoint_security_group_id" {
  description = "ID of the security group attached to interface VPC endpoints. Null when endpoints are disabled."
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}

output "gateway_vpc_endpoint_ids" {
  description = "Map of service short-name (s3, dynamodb) → VPC endpoint ID for gateway endpoints."
  value       = { for service, ep in aws_vpc_endpoint.gateway : service => ep.id }
}

output "gateway_vpc_endpoint_prefix_lists" {
  description = "Map of service short-name → managed prefix list ID. Useful for security-group rules that allow egress only to a specific gateway endpoint."
  value       = { for service, ep in aws_vpc_endpoint.gateway : service => ep.prefix_list_id }
}

output "interface_vpc_endpoint_ids" {
  description = "Map of service short-name → VPC endpoint ID for interface endpoints."
  value       = { for service, ep in aws_vpc_endpoint.interface : service => ep.id }
}

output "interface_vpc_endpoint_dns_entries" {
  description = "Map of service short-name → list of DNS entries (zone + DNS name) the endpoint exposes inside the VPC."
  value       = { for service, ep in aws_vpc_endpoint.interface : service => ep.dns_entry }
}


# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------
output "waf_web_acl_id" {
  description = "ID of the WAF v2 WebACL. Null when WAF is disabled."
  value       = try(aws_wafv2_web_acl.main[0].id, null)
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF v2 WebACL. The environment composition will associate this with the ALB."
  value       = try(aws_wafv2_web_acl.main[0].arn, null)
}

output "waf_log_group_name" {
  description = "Name of the CloudWatch log group receiving WAF logs."
  value       = try(aws_cloudwatch_log_group.waf[0].name, null)
}


# -----------------------------------------------------------------------------
# Diagnostic
# -----------------------------------------------------------------------------
output "iam_password_policy_managed" {
  description = "Whether this module is managing the AWS account password policy. Useful for auditing which terraform module owns the policy in multi-environment setups."
  value       = var.enable_iam_password_policy
}

output "default_ebs_encryption_managed" {
  description = "Whether this module is managing default EBS encryption for the AWS account+region."
  value       = var.enable_default_ebs_encryption
}
