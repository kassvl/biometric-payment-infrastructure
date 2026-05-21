# =============================================================================
# Customer-Managed KMS Key (CMK) for encrypting the Terraform state bucket.
#
# Why a CMK instead of the AWS-managed `aws/s3` key:
#   - The key policy is fully under our control: we can grant or revoke access
#     per IAM principal. The aws/s3 key cannot be policy-restricted by us.
#   - Annual key rotation is enabled — required by PCI-DSS 3.6.4.
#   - Every cryptographic operation appears in CloudTrail under our key ARN,
#     giving us a clean audit trail.
#   - We can scope grants to specific roles (CI apply roles) without granting
#     blanket KMS permissions.
# =============================================================================

resource "aws_kms_key" "tfstate" {
  description             = "CMK for ${var.project_name} Terraform remote state encryption (S3 + DynamoDB)"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = false
  policy                  = data.aws_iam_policy_document.kms_tfstate.json

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-tfstate-cmk"
    Purpose = "tfstate-encryption"
  })
}

resource "aws_kms_alias" "tfstate" {
  name          = var.kms_alias
  target_key_id = aws_kms_key.tfstate.key_id
}

# -----------------------------------------------------------------------------
# Key policy
#
# Two statements:
#   1. The account root retains full administrative access. Without this, a
#      key with a too-restrictive policy can become unmanageable ("locking
#      yourself out of the key") and is recoverable only by AWS Support.
#   2. The S3 service is allowed to use this key for encrypt/decrypt operations
#      ONLY when the request originates from our own account. This guards
#      against the "confused deputy" problem where another account names our
#      bucket and tries to call S3 against it.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "kms_tfstate" {
  statement {
    sid    = "AllowAccountRootAdmin"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3UseFromOwnAccount"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowDynamoDBUseFromOwnAccount"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dynamodb.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}
