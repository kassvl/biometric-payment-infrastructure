# =============================================================================
# Outputs consumed by composing environments and downstream modules.
#
# Subnets are emitted both as maps (keyed by AZ) and as lists (in AZ-order)
# so consumers can pick whichever shape is more convenient.
# =============================================================================


# -----------------------------------------------------------------------------
# VPC core
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC. Required by virtually every other module."
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.main.id
}

output "default_security_group_id" {
  description = "ID of the (stripped) default Security Group. Should NOT be used by workloads; downstream modules create purpose-built SGs."
  value       = aws_default_security_group.main.id
}

output "azs" {
  description = "List of AZs the subnets are spread across (echoed from input for downstream convenience)."
  value       = var.azs
}


# -----------------------------------------------------------------------------
# Subnets — public
# -----------------------------------------------------------------------------
output "public_subnet_ids" {
  description = "Ordered list of public subnet IDs, aligned with var.azs."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "public_subnets_by_az" {
  description = "Map of AZ → public subnet ID."
  value       = { for az in var.azs : az => aws_subnet.public[az].id }
}

output "public_subnet_cidrs" {
  description = "Ordered list of public subnet CIDRs."
  value       = [for az in var.azs : aws_subnet.public[az].cidr_block]
}


# -----------------------------------------------------------------------------
# Subnets — private app
# -----------------------------------------------------------------------------
output "private_app_subnet_ids" {
  description = "Ordered list of private-app subnet IDs (EKS workers go here)."
  value       = [for az in var.azs : aws_subnet.private_app[az].id]
}

output "private_app_subnets_by_az" {
  description = "Map of AZ → private-app subnet ID."
  value       = { for az in var.azs : az => aws_subnet.private_app[az].id }
}


# -----------------------------------------------------------------------------
# Subnets — private db
# -----------------------------------------------------------------------------
output "private_db_subnet_ids" {
  description = "Ordered list of private-db subnet IDs (Aurora, ElastiCache)."
  value       = [for az in var.azs : aws_subnet.private_db[az].id]
}

output "private_db_subnets_by_az" {
  description = "Map of AZ → private-db subnet ID."
  value       = { for az in var.azs : az => aws_subnet.private_db[az].id }
}


# -----------------------------------------------------------------------------
# NAT
# -----------------------------------------------------------------------------
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs in AZ order. Empty if NAT is disabled."
  value       = [for az in local.nat_gateway_azs : aws_nat_gateway.main[az].id]
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IPs assigned to the NAT Gateways. These are the source IPs the internet sees for any private-subnet egress."
  value       = [for az in local.nat_gateway_azs : aws_eip.nat[az].public_ip]
}


# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------
output "public_route_table_id" {
  description = "ID of the (single) public route table."
  value       = aws_route_table.public.id
}

output "private_app_route_table_ids" {
  description = "List of private-app route table IDs in AZ order."
  value       = [for az in var.azs : aws_route_table.private_app[az].id]
}

output "private_db_route_table_ids" {
  description = "List of private-db route table IDs in AZ order."
  value       = [for az in var.azs : aws_route_table.private_db[az].id]
}


# -----------------------------------------------------------------------------
# Flow Logs
# -----------------------------------------------------------------------------
output "flow_log_id" {
  description = "ID of the VPC Flow Log resource (null if flow logs are disabled)."
  value       = try(aws_flow_log.main[0].id, null)
}

output "flow_log_group_name" {
  description = "Name of the CloudWatch log group receiving flow logs (null if disabled)."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}

output "flow_log_group_arn" {
  description = "ARN of the CloudWatch log group receiving flow logs (null if disabled)."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].arn, null)
}
