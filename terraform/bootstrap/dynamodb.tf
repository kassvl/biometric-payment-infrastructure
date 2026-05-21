# =============================================================================
# DynamoDB state lock table.
#
# Without locking, two engineers (or two CI jobs) running `terraform apply`
# at the same time would race-write the state file, corrupting it. Terraform
# acquires a row-level lock in this table for the duration of every apply.
#
# Hash key MUST be named "LockID" — Terraform's S3 backend hard-codes this.
# =============================================================================

resource "aws_dynamodb_table" "tfstate_lock" {
  name = var.dynamodb_table_name

  # PAY_PER_REQUEST is the right choice for a lock table:
  #   - Traffic pattern is bursty (one request per terraform plan/apply).
  #   - Provisioned capacity would be over-provisioned 99% of the time.
  #   - Cost: typically <$0.50/month for a normal team.
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Encryption at rest with our customer-managed KMS key. CloudTrail will
  # record every cryptographic operation against the table.
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.tfstate.arn
  }

  # Continuous backups + point-in-time recovery. If the lock table is ever
  # accidentally truncated or corrupted, we can restore to any second within
  # the last 35 days.
  point_in_time_recovery {
    enabled = true
  }

  # TTL attribute is optional for Terraform locks (Terraform releases the lock
  # on its own success path), but is here as a safety net: if a process is
  # killed mid-apply and leaves a stale lock, an operator can write a TTL
  # value into the row to allow DynamoDB to expire it without manual deletion.
  ttl {
    attribute_name = "TTL"
    enabled        = true
  }

  # Deletion protection blocks accidental `terraform destroy` of the lock
  # table itself. Disabled only when the operator opts into force_destroy
  # (e.g., tearing down a sandbox account).
  deletion_protection_enabled = !var.force_destroy

  tags = merge(local.common_tags, {
    Name    = var.dynamodb_table_name
    Purpose = "tfstate-lock"
  })
}
