# =============================================================================
# Identity / partition data sources.
#
# - aws_caller_identity gives us the AWS account ID, used to make global
#   resource names (S3 buckets) unique.
# - aws_partition is 'aws' in commercial regions and 'aws-cn' / 'aws-us-gov'
#   in partitioned regions. We compose ARNs through this so the module also
#   works in non-commercial partitions.
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
