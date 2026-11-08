# House copy of Cloud Posse's aws-config-bucket component
# (github.com/cloudposse-terraform-components/aws-config-bucket, src/ at v1.535.1),
# with Cloud Posse's account-map-bypass providers and account-verification mixins
# (cloudposse-terraform-components/mixins v0.5.0, copied unchanged).
#
# Deviations from upstream:
#   - cloudposse/config-storage/aws 1.0.2 is inlined (E5a4b, owner 2026-11-05): this file
#     calls the module config-storage wraps, cloudposse/s3-log-storage/aws 1.4.1, with
#     config-storage's arguments and its three bucket policy statements restated, because
#     config-storage builds the bucket policy from its own statements only and ignores its
#     `policy` input, so no Deny could be added. Two Denys are added to its statements:
#     config.amazonaws.com may put an object only for an aws:SourceAccount of this bucket's
#     residency (residency_account_ids), and only under this bucket's key. Two Allows add this
#     account's own recorder role (E5b4b): a same-account recorder delivers with its role.
#   - The bucket is encrypted with a customer managed KMS key (E5a3): sse_algorithm is
#     "aws:kms" and kms_master_key_arn is a required input. Upstream hardcodes "AES256".
#   - enable_glacier_transition is passed through (upstream declares it but never wires it).
#   - Upstream's acl input is dropped: config-storage hardcodes acl "private".
#   - allow_ssl_requests_only is true (E5a4): config-storage defaults it to false.
# Everything else (inputs, defaults, outputs, naming from the null-label context) is
# upstream's. Diff against upstream and config-storage 1.0.2 before a refresh.

locals {
  # The residency: the explicit list, or every account of the static account map but
  # <tenant>-prod-eu (the US residency, as aws-cloudtrail-bucket's policy_override.tf derives it),
  # so a new account cannot be missed.
  residency_account_ids = var.residency_account_ids != null ? var.residency_account_ids : distinct([
    for name, id in var.account_map.full_account_map : id if name != "${module.this.tenant}-prod-eu"
  ])
  s3_bucket_arn    = format("arn:%s:s3:::%s", data.aws_partition.current.partition, module.aws_config_label.id)
  s3_object_prefix = format("%s/AWSLogs/*", local.s3_bucket_arn)
  # This account's own recorder role: its home stack's (<tenant>-ue1-<stage>) aws-config role,
  # which its eu-west-1 recorder reuses (catalog/aws-config main-core-region's convention ARN).
  recorder_role_arn = format("arn:%s:iam::%s:role/%s-ue1-%s-aws-config-config",
  data.aws_partition.current.partition, data.aws_caller_identity.current.account_id, module.this.tenant, module.this.stage)
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# The bucket name config-storage gives s3-log-storage (attributes "aws-config").
module "aws_config_label" {
  #checkov:skip=CKV_TF_1:Cloud Posse's null-label registry module pinned to an exact version, as config-storage 1.0.2 calls it
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["aws-config"]
  context    = module.this.context
}

module "config_bucket" {
  #checkov:skip=CKV_TF_1:Cloud Posse's registry module pinned to an exact version, as config-storage 1.0.2 calls it
  source  = "cloudposse/s3-log-storage/aws"
  version = "1.4.1"
  count   = module.this.enabled ? 1 : 0

  acl                                    = "private"
  lifecycle_prefix                       = ""
  lifecycle_tags                         = {}
  force_destroy                          = false
  lifecycle_rule_enabled                 = var.lifecycle_rule_enabled
  versioning_enabled                     = true
  noncurrent_version_expiration_days     = var.noncurrent_version_expiration_days
  noncurrent_version_transition_days     = var.noncurrent_version_transition_days
  standard_transition_days               = var.standard_transition_days
  glacier_transition_days                = var.glacier_transition_days
  enable_glacier_transition              = var.enable_glacier_transition
  expiration_days                        = var.expiration_days
  abort_incomplete_multipart_upload_days = 5
  sse_algorithm                          = "aws:kms"
  kms_master_key_arn                     = var.kms_master_key_arn
  block_public_acls                      = true
  block_public_policy                    = true
  ignore_public_acls                     = true
  restrict_public_buckets                = true
  access_log_bucket_name                 = var.access_log_bucket_name
  allow_ssl_requests_only                = true
  source_policy_documents                = [join("", data.aws_iam_policy_document.aws_config_bucket_policy[*].json)]

  tags       = module.this.tags
  attributes = ["aws-config"]
  context    = module.this.context
}

data "aws_iam_policy_document" "aws_config_bucket_policy" {
  count = module.this.enabled ? 1 : 0

  # config-storage 1.0.2's three statements, unchanged.
  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.s3_bucket_arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSConfigBucketExistenceCheck"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.s3_bucket_arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = [local.s3_object_prefix]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # House: AWS Config delivers to a bucket of its own account with the recorder's IAM role, not
  # config.amazonaws.com, so this account's recorder gets the three statements above by role
  # (E5b4b). The principal is "*" narrowed by aws:PrincipalArn: S3 rejects a policy naming a role
  # that does not exist yet, and the recorder is created after its bucket. A fixed
  # aws:PrincipalArn keeps the policy non-public (block_public_policy). The Denys below name the
  # service principal only, so they do not match this role.
  statement {
    sid       = "AWSConfigRoleBucketChecks"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [local.s3_bucket_arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.recorder_role_arn]
    }
  }

  statement {
    sid       = "AWSConfigRoleDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = [local.s3_object_prefix]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.recorder_role_arn]
    }
    condition {
      test     = "StringLike"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # House: no delivery for a source account outside the residency. StringNotEquals is true when
  # aws:SourceAccount is absent, so a request without it is denied too (fails closed).
  statement {
    sid       = "DenyDeliveryOutsideResidency"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.s3_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceAccount"
      values   = local.residency_account_ids
    }
  }

  # House: no delivery under another KMS key (a recorder's own s3KmsKeyArn). IfExists lets a put
  # with no key header through: the bucket's default encryption applies this key.
  statement {
    sid       = "DenyDeliveryUnderOtherKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.s3_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.kms_master_key_arn]
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.residency_account_ids) > 0
      error_message = "The residency is empty: set residency_account_ids, or account_map.full_account_map (the account-map-bypass abstract) to derive it."
    }
    precondition {
      condition     = var.residency_account_ids != null || startswith(var.region, "eu-") == false
      error_message = "An eu- region bucket must set residency_account_ids: the derived default is the US residency (every account but prod-eu)."
    }
  }
}
