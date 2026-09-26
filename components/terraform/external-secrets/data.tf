# Used to scope the external-secrets IAM policy to this account, region and
# partition instead of the "*:*" wildcards Secrets Manager/SSM/KMS accept in
# ARNs. aws_partition matters in GovCloud/China accounts, where resource ARNs
# use "aws-us-gov"/"aws-cn" instead of "aws" (var.kms_key_arn already accepts
# those partitions; the Secrets Manager/SSM ARNs built in main.tf must match).
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
