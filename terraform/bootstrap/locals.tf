# =============================================================================
# Local values: computed names and common tags.
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Bucket names default to "<project>-<purpose>-<account-id>" so they are
  # unique across the AWS partition (S3 bucket names are global).
  state_bucket_name = coalesce(
    var.state_bucket_name,
    "${var.project_name}-tfstate-${local.account_id}"
  )

  log_bucket_name = coalesce(
    var.log_bucket_name,
    "${var.project_name}-tfstate-logs-${local.account_id}"
  )

  # Tags applied to every resource. Module-level tags + caller-provided extras.
  # default_tags in the provider block also applies a smaller set; resource-level
  # tags here override and extend those.
  common_tags = merge(
    {
      Project            = var.project_name
      Environment        = var.environment
      Owner              = "platform-team"
      CostCenter         = "platform"
      DataClassification = "confidential"
      ManagedBy          = "Terraform"
      Module             = "bootstrap"
      Repository         = "kassvl/biometric-payment-infrastructure"
    },
    var.extra_tags,
  )
}
