# Current AWS account ID
data "aws_caller_identity" "current" {}

# Current AWS region
data "aws_region" "current" {}

# Current partition
data "aws_partition" "current" {}
