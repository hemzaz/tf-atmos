# House override of the vendored Cloud Posse aws-identity-center (vendor.yaml)
# policy-TerraformAccess.tf: the TerraformPlanAccess* permission sets assume a
# backend's READ role, not its write role. Upstream has one state role per
# backend, so its Plan sets assume tf_access_role_arn / role_arn, the role the
# Apply and State sets assume too. Here every backend splits its access roles
# by stage into read and write roles (stacks/catalog/backend), and a backend
# trusts the Plan sets only on its read roles, the Apply sets only on its write
# roles (owner decision 2026-11-04; stacks/orgs/fnx/root/us-east-1.yaml).
#
#   - TerraformPlanAccess (the main backend): tf_access_role_arn's read twin,
#     "<role_prefix>-role" -> "<role_prefix>-read-role" (catalog/backend/roles/nonprod);
#     an ARN not ending in "-role" fails the plan (regex), never falls back to
#     the write role. (An override cannot add a validation block.)
#   - TerraformPlanAccess-<Key>: the additional backend's read_role_arn, a field
#     this override adds (optional, no default: an override's type keeps the
#     base declaration's optional() defaults, so an omitted field is null); a
#     backend without one (core: its stacks have no read role) gets no state
#     role to assume.
#
# Terraform replaces every nested "statement" of an overridden data source, so
# each document below restates upstream's statements (sids, actions, the S3
# read and EC2DescribeRegions) with only the assumed role changed;
# scripts/check-identity-center-override.py (lint) fails when a vendor bump
# changes upstream's statements or the variable's fields.

variable "tf_access_additional_backends" {
  type = map(object({
    bucket_arn         = string
    dynamodb_table_arn = optional(string, "")
    role_arn           = string
    read_role_arn      = optional(string)
  }))
}

data "aws_iam_policy_document" "terraform_plan_access" {
  statement {
    sid       = "TerraformStateBackendS3BucketReadOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [var.tf_access_bucket_arn, "${var.tf_access_bucket_arn}/*"]
  }

  statement {
    sid       = "TerraformStateBackendAssumeRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
    resources = ["${regex("^(.+)-role$", var.tf_access_role_arn)[0]}-read-role"]
  }

  statement {
    sid       = "EC2DescribeRegions"
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "terraform_plan_access_additional" {
  statement {
    sid       = "TerraformStateBackendS3BucketReadOnly"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [each.value.bucket_arn, "${each.value.bucket_arn}/*"]
  }

  statement {
    sid       = "EC2DescribeRegions"
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = compact([each.value.read_role_arn])

    content {
      sid       = "TerraformStateBackendAssumeRole"
      effect    = "Allow"
      actions   = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
      resources = [statement.value]
    }
  }
}
