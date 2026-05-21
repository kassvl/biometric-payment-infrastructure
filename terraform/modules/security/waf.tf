# =============================================================================
# AWS WAF v2 — Regional WebACL.
#
# Created here, ASSOCIATED with an ALB by the environment composition once
# the ALB exists. Splitting creation from association keeps this module
# free of cross-module circular dependencies.
#
# Default action is ALLOW — rules below explicitly block known-bad patterns
# and rate-limit abusive sources. Inverting to default-DENY is too disruptive
# for a public payment site without a per-rule allowlist.
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch log group for WAF logs.
# WAF requires the log group name to start with "aws-waf-logs-".
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.waf_log_retention_days

  # Use our logs CMK if it was created; otherwise leave AWS-managed.
  kms_key_id = try(aws_kms_key.this["logs"].arn, null)

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-waf-logs"
    Purpose = "waf-v2-logs"
  })
}

# -----------------------------------------------------------------------------
# WebACL.
#
# Rule order matters — lower priority numbers run first. We put the IP
# reputation list at priority 1 so we drop known-malicious sources before
# spending CPU on signature matches.
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.name_prefix}-webacl"
  description = "Regional WAF v2 WebACL for ${local.name_prefix} - managed rules + custom rate limit."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ---------------------------------------------------------------------------
  # Rule 1: Drop traffic from IPs AWS has classified as malicious.
  # ---------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 2: Drop traffic from anonymizing services (Tor, public proxies, VPNs)
  # for the payment endpoints. Anonymizing IPs are common in card-fraud rings.
  # ---------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesAnonymousIpList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAnonymousIpList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAnonymousIpList"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 3: AWS Common Rule Set (OWASP Top-10 baseline).
  # ---------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 4: AWS Known Bad Inputs (exploits with known signatures).
  # ---------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 11

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 5: SQLi rule set — injection patterns in query strings and bodies.
  # ---------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 12

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 6: Per-IP rate limit. Requests above the threshold over any 5-minute
  # window from one IP are blocked. Threshold is configurable per environment.
  # ---------------------------------------------------------------------------
  rule {
    name     = "RateLimitPerSourceIp"
    priority = 100

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerSourceIp"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-webacl"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-webacl"
  })
}

# -----------------------------------------------------------------------------
# Logging configuration — WAF logs sampled requests + blocks to CloudWatch.
# -----------------------------------------------------------------------------
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.main[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Redact common sensitive fields from logs (authorization headers, cookies).
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
