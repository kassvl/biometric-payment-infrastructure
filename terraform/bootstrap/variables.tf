# =============================================================================
# Input variables for the bootstrap module.
#
# All variables have a type, a description, and (where useful) a validation
# block. None of them carry secrets.
# =============================================================================

variable "project_name" {
  description = "Short, lowercase identifier used as a prefix on every bootstrap resource name. Must be unique across the AWS partition because S3 bucket names are global."
  type        = string
  default     = "biopay"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be 2-20 characters: lowercase letters, digits, and hyphens only."
  }
}

variable "region" {
  description = "AWS region in which the state bucket, log bucket, KMS key, and lock table are created. This should match the region of the workloads they back, so apply latency is minimal."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "region must look like 'eu-central-1', 'us-east-1', etc."
  }
}

variable "environment" {
  description = "Environment tag for the bootstrap resources themselves. The bootstrap module is shared across dev/prod, so the value 'shared' is correct."
  type        = string
  default     = "shared"
}

variable "state_bucket_name" {
  description = "Optional override for the state bucket name. If null, resolves to '<project>-tfstate-<account-id>'. Override only if you need to import an existing bucket."
  type        = string
  default     = null
}

variable "log_bucket_name" {
  description = "Optional override for the access log bucket name. If null, resolves to '<project>-tfstate-logs-<account-id>'."
  type        = string
  default     = null
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB lock table that serializes concurrent `terraform apply` runs across all environments using this backend."
  type        = string
  default     = "biopay-tfstate-locks"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name must be 3-255 chars and contain only letters, digits, dot, dash, underscore."
  }
}

variable "kms_alias" {
  description = "KMS alias for the customer-managed key encrypting the state bucket. Must start with 'alias/'."
  type        = string
  default     = "alias/biopay-tfstate"

  validation {
    condition     = startswith(var.kms_alias, "alias/")
    error_message = "kms_alias must start with 'alias/' (e.g. 'alias/biopay-tfstate')."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Days to wait before the KMS key is permanently deleted after destroy. AWS supports 7-30; 30 is the safe default for state encryption keys."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent versions of state objects are deleted. Current versions are never expired by lifecycle. 365 keeps a year of recovery history."
  type        = number
  default     = 365

  validation {
    condition     = var.noncurrent_version_expiration_days >= 30
    error_message = "noncurrent_version_expiration_days must be at least 30 days to support recovery from accidental writes."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain S3 server access logs. 2557 (~7 years) aligns with FinTech audit windows (PCI-DSS, DORA)."
  type        = number
  default     = 2557

  validation {
    condition     = var.log_retention_days >= 365
    error_message = "log_retention_days must be at least 365 days for any FinTech-grade audit posture."
  }
}

variable "force_destroy" {
  description = "If true, allows non-empty buckets to be destroyed by `terraform destroy`. NEVER set to true in production: state and audit logs would be permanently lost. Acceptable only when bootstrapping a throw-away sandbox account."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource on top of the module's own common tags."
  type        = map(string)
  default     = {}
}
