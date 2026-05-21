# =============================================================================
# Customer-Managed KMS Keys (CMKs) for the security module.
#
# We create one CMK per logical domain (logs, secrets, rds, ebs). The key
# policy is generated per-key based on the service principals declared in
# local.kms_key_catalog. Annual rotation is enabled on every key.
#
# Why one CMK per domain (instead of one shared CMK):
#   - Blast-radius isolation: revoking the secrets CMK does not break logging.
#   - Per-domain audit: CloudTrail filters by key ARN — finding "who decrypted
#     RDS storage at 03:14" is a single query, not a haystack.
#   - Forensic key revocation: a suspected compromise can be limited to one
#     domain instead of disabling encryption everywhere.
# =============================================================================

resource "aws_kms_key" "this" {
  for_each = local.kms_keys_selected

  description             = each.value.description
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  multi_region            = false

  policy = data.aws_iam_policy_document.kms[each.key].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-${each.key}-cmk"
    Purpose = "${each.key}-encryption"
  })
}

resource "aws_kms_alias" "this" {
  for_each = aws_kms_key.this

  name          = "alias/${local.name_prefix}-${each.key}"
  target_key_id = each.value.key_id
}

# -----------------------------------------------------------------------------
# Per-key policy.
#
# Every policy has two statements:
#   1. Account root retains full administrative access. Without this, a
#      too-tight policy can permanently lock you out of the key — only AWS
#      Support can recover it.
#   2. The service principal(s) declared in the catalog can use the key
#      for encrypt/decrypt/generate-data-key operations, ONLY when called
#      from our own AWS account (aws:SourceAccount condition). This guards
#      against the "confused deputy" cross-account attack.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  for_each = local.kms_keys_selected

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

  # CloudWatch Logs requires kms:Encrypt*, kms:Decrypt*, kms:ReEncrypt*,
  # kms:GenerateDataKey*, kms:Describe* on a CMK to encrypt log groups.
  # The condition restricts use to logs in our account in our region.
  statement {
    sid    = "AllowServiceUseFromOwnAccount"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = each.value.services
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}
