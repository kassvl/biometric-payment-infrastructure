# =============================================================================
# S3 buckets for the bootstrap module.
#
# Two buckets are created:
#   1. Access log bucket — receives S3 server access logs from the state bucket.
#   2. State bucket      — holds remote Terraform state for every other module.
#
# The log bucket is created and policy-applied first so the state bucket's
# logging configuration succeeds on first apply.
# =============================================================================


# -----------------------------------------------------------------------------
# (1) Access log bucket
#
# S3 server access logs cannot be encrypted with a KMS-CMK at the destination
# (S3 log delivery does not support KMS yet). AES-256 (SSE-S3) is the AWS-
# recommended pattern. Versioning is intentionally NOT enabled — log objects
# are immutable by convention and we don't need version sprawl on append-only
# delivery.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  bucket        = local.log_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name    = local.log_bucket_name
    Purpose = "tfstate-access-logs"
  })
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs.json
}

data "aws_iam_policy_document" "logs" {
  # Reject every connection that is not TLS. PCI-DSS 4.x requirement.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow the S3 logging service to deliver access logs from the state bucket
  # only. Scoped by source ARN and source account so no other bucket (in any
  # account) can deposit logs here.
  statement {
    sid    = "AllowS3LogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:s3:::${local.state_bucket_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}


# -----------------------------------------------------------------------------
# (2) State bucket
#
# Holds Terraform state for every environment. Versioning is mandatory: it is
# the only way to recover from accidental delete or to retrieve a known-good
# state if a corruption is suspected. SSE uses our CMK, not the default
# aws/s3 key.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.state_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name    = local.state_bucket_name
    Purpose = "tfstate"
  })
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
    # MFA delete intentionally NOT enabled: it requires the bucket-owning
    # AWS account root to provide an MFA token on every delete. This blocks
    # lifecycle automation entirely. Use bucket policy + IAM SCPs instead.
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
    # Bucket Key reduces KMS API calls and cost by reusing a per-bucket
    # data key for short windows; AES envelope encryption is unchanged.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access/"

  # Order matters: the log bucket policy must be applied before logging is
  # enabled, otherwise the first delivery attempt is denied.
  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "manage-noncurrent-versions"
    status = "Enabled"

    filter {}

    # Move noncurrent versions to cheaper storage 30 days after they become
    # noncurrent. Current state objects are unaffected.
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    # Permanently remove noncurrent versions after the configured window.
    # The current version of every state file is never expired by lifecycle.
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json
}

data "aws_iam_policy_document" "tfstate" {
  # Deny every non-TLS connection. PCI-DSS 4.x; CIS S3 1.7.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Reject any PutObject that does not specify aws:kms server-side encryption.
  # This catches a misconfigured client that bypasses the bucket default
  # (e.g., AWS CLI with --no-server-side-encryption).
  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  # Reject PUTs that specify the wrong KMS key. Ensures every object lands
  # encrypted under our CMK and not under aws/s3 or another account's key.
  statement {
    sid    = "DenyWrongKmsKey"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.tfstate.arn]
    }
  }
}
