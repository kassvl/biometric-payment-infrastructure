# =============================================================================
# EBS default encryption — account+region singleton.
#
# When enabled, every new EBS volume in this account+region is encrypted
# at rest by default, even if the caller forgot to specify encryption.
# The default key is set to our 'ebs' CMK so volumes encrypt under the
# key whose policy and audit trail we control.
#
# Caveat: if multiple environments call this module against the same
# AWS account+region, set enable_default_ebs_encryption=true in only one.
# =============================================================================

resource "aws_ebs_encryption_by_default" "main" {
  count = var.enable_default_ebs_encryption ? 1 : 0

  enabled = true
}

resource "aws_ebs_default_kms_key" "main" {
  count = var.enable_default_ebs_encryption && contains(var.kms_keys_to_create, "ebs") ? 1 : 0

  key_arn = aws_kms_key.this["ebs"].arn

  # The encryption-by-default toggle must be on before the default key can
  # be set; sequencing avoids a race.
  depends_on = [aws_ebs_encryption_by_default.main]
}
