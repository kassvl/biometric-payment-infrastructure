# =============================================================================
# Outputs consumed by downstream Terraform environments.
#
# After `terraform apply` succeeds in this module, copy the relevant values
# into each environment's `backend.tf`. The `backend_config_snippet` output
# is a paste-ready block that does this for you.
# =============================================================================

output "state_bucket_id" {
  description = "Name of the S3 bucket holding remote Terraform state. Use as the `bucket` argument in every downstream `backend \"s3\" {}` block."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket. Useful for IAM policy targeting (CI roles, replication policies, etc.)."
  value       = aws_s3_bucket.tfstate.arn
}

output "state_bucket_region" {
  description = "Region of the state bucket. Equal to var.region but emitted explicitly so backends can reference it without re-typing."
  value       = var.region
}

output "log_bucket_id" {
  description = "Name of the S3 bucket receiving server access logs from the state bucket."
  value       = aws_s3_bucket.logs.id
}

output "log_bucket_arn" {
  description = "ARN of the access log bucket."
  value       = aws_s3_bucket.logs.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB lock table. Use as the `dynamodb_table` argument in `backend \"s3\" {}`."
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lock table."
  value       = aws_dynamodb_table.tfstate_lock.arn
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting state at rest. Use as `kms_key_id` in `backend \"s3\" {}` (alias also acceptable)."
  value       = aws_kms_key.tfstate.arn
}

output "kms_key_id" {
  description = "Plain key ID (no ARN prefix) of the state-encryption KMS key."
  value       = aws_kms_key.tfstate.key_id
}

output "kms_key_alias" {
  description = "Alias of the state-encryption KMS key (alias/...). Preferred over the raw key ID because it is human-readable and survives key rotation/replacement."
  value       = aws_kms_alias.tfstate.name
}

output "backend_config_snippet" {
  description = "Drop-in `backend \"s3\" {}` configuration for a downstream environment. Replace `<env>` with the target environment name (e.g. `dev`, `prod`)."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "<env>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
        encrypt        = true
        kms_key_id     = "${aws_kms_alias.tfstate.name}"
      }
    }
  EOT
}
