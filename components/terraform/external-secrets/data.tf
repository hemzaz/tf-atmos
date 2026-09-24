# Used to scope the external-secrets IAM policy to this account and region
# instead of the "*:*" wildcards Secrets Manager/SSM/KMS accept in ARNs.
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
