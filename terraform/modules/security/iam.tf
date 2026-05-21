# =============================================================================
# IAM account password policy.
#
# This is an ACCOUNT-WIDE singleton: there is exactly one password policy
# per AWS account. If multiple environments call this module against the
# same account, only ONE of them must set enable_iam_password_policy=true
# (typically prod, or a dedicated account-baseline environment).
#
# In a real org, this is usually managed at the AWS Organizations level
# via a service-control policy. We codify it here so a single-account
# deployment still gets the control.
# =============================================================================

resource "aws_iam_account_password_policy" "main" {
  count = var.enable_iam_password_policy ? 1 : 0

  minimum_password_length        = var.password_min_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  hard_expiry                    = false
  max_password_age               = var.password_max_age
  password_reuse_prevention      = var.password_reuse_prevention
}
