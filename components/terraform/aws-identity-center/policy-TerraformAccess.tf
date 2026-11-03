# Shared variables for Terraform state backend access
variable "tf_access_bucket_arn" {
  type        = string
  description = "The ARN of the S3 bucket for the Terraform state backend."
  default     = ""
}

variable "tf_access_dynamodb_table_arn" {
  type        = string
  description = "The ARN of the DynamoDB table for the Terraform state backend."
  default     = ""
}

variable "tf_access_role_arn" {
  type        = string
  description = "The ARN of the IAM role for accessing the Terraform state backend."
  default     = ""
}

variable "tf_access_additional_backends" {
  type = map(object({
    bucket_arn         = string
    dynamodb_table_arn = optional(string, "")
    role_arn           = string
  }))
  description = <<-EOT
    Map of additional Terraform state backends to grant SSO permission sets access to.
    Each entry creates three permission sets: TerraformPlanAccess-<key>, TerraformApplyAccess-<key>, and TerraformStateAccess-<key>.

    The map key should be a descriptive name for the backend (e.g., "core", "plat", "prod").
    This key will be title-cased and appended to the permission set names with a hyphen.

    Example:
    ```
    tf_access_additional_backends = {
      core = {
        bucket_arn         = "arn:aws:s3:::example-core-tfstate"
        dynamodb_table_arn = "arn:aws:dynamodb:us-east-1:123456789012:table/example-core-tfstate-lock"
        role_arn           = "arn:aws:iam::123456789012:role/example-core-gbl-root-tfstate"
      }
      plat = {
        bucket_arn = "arn:aws:s3:::example-plat-tfstate"
        role_arn   = "arn:aws:iam::123456789012:role/example-plat-gbl-root-tfstate"
      }
    }
    ```
  EOT
  default     = {}
}

locals {
  tf_access_enabled = local.enabled && var.tf_access_bucket_arn != "" && var.tf_access_role_arn != ""

  # Additional backends access
  tf_access_additional_backends_enabled = local.enabled && length(var.tf_access_additional_backends) > 0

  # Helper to title-case the backend names for permission set names
  # "core" -> "Core", "plat" -> "Plat", "prod-us-east-1" -> "ProdUsEast1"
  backend_names_titlecase = {
    for key, config in var.tf_access_additional_backends :
    key => join("", [for part in split("-", key) : title(part)])
  }

  # Terraform Plan Access permission set
  terraform_plan_access_permission_set = local.tf_access_enabled ? [{
    name                                = "TerraformPlanAccess",
    description                         = "Allow read-only access to Terraform state for planning",
    relay_state                         = "",
    session_duration                    = var.session_duration,
    tags                                = {},
    inline_policy                       = one(data.aws_iam_policy_document.terraform_plan_access[*].json),
    policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/ReadOnlyAccess"]
    customer_managed_policy_attachments = []
  }] : []

  # Terraform Apply Access permission set
  terraform_apply_access_permission_set = local.tf_access_enabled ? [{
    name                                = "TerraformApplyAccess",
    description                         = "Allow full access to Terraform state and account for applying changes",
    relay_state                         = "",
    session_duration                    = var.session_duration,
    tags                                = {},
    inline_policy                       = one(data.aws_iam_policy_document.terraform_apply_access[*].json),
    policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/AdministratorAccess"]
    customer_managed_policy_attachments = []
  }] : []

  # Terraform State Access permission set
  terraform_state_access_permission_set = local.tf_access_enabled ? [{
    name                                = "TerraformStateAccess",
    description                         = "Allow read/write access to Terraform state backend only",
    relay_state                         = "",
    session_duration                    = var.session_duration,
    tags                                = {},
    inline_policy                       = one(data.aws_iam_policy_document.terraform_state_access[*].json),
    policy_attachments                  = []
    customer_managed_policy_attachments = []
  }] : []

  # Additional backends permission sets
  terraform_plan_access_additional_permission_sets = local.tf_access_additional_backends_enabled ? [
    for key, config in var.tf_access_additional_backends : {
      name                                = "TerraformPlanAccess-${local.backend_names_titlecase[key]}"
      description                         = "Allow read-only access to Terraform state for planning (${key} backend)"
      relay_state                         = ""
      session_duration                    = var.session_duration
      tags                                = {}
      inline_policy                       = data.aws_iam_policy_document.terraform_plan_access_additional[key].json
      policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/ReadOnlyAccess"]
      customer_managed_policy_attachments = []
    }
  ] : []

  terraform_apply_access_additional_permission_sets = local.tf_access_additional_backends_enabled ? [
    for key, config in var.tf_access_additional_backends : {
      name                                = "TerraformApplyAccess-${local.backend_names_titlecase[key]}"
      description                         = "Allow full access to Terraform state and account for applying changes (${key} backend)"
      relay_state                         = ""
      session_duration                    = var.session_duration
      tags                                = {}
      inline_policy                       = data.aws_iam_policy_document.terraform_apply_access_additional[key].json
      policy_attachments                  = ["arn:${local.aws_partition}:iam::aws:policy/AdministratorAccess"]
      customer_managed_policy_attachments = []
    }
  ] : []

  terraform_state_access_additional_permission_sets = local.tf_access_additional_backends_enabled ? [
    for key, config in var.tf_access_additional_backends : {
      name                                = "TerraformStateAccess-${local.backend_names_titlecase[key]}"
      description                         = "Allow read/write access to Terraform state backend only (${key} backend)"
      relay_state                         = ""
      session_duration                    = var.session_duration
      tags                                = {}
      inline_policy                       = data.aws_iam_policy_document.terraform_state_access_additional[key].json
      policy_attachments                  = []
      customer_managed_policy_attachments = []
    }
  ] : []
}

# Terraform Plan Access - Read-only state access, read-only account access
data "aws_iam_policy_document" "terraform_plan_access" {
  count = local.tf_access_enabled ? 1 : 0

  # Read-only access to Terraform state S3 bucket
  statement {
    sid    = "TerraformStateBackendS3BucketReadOnly"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [var.tf_access_bucket_arn, "${var.tf_access_bucket_arn}/*"]
  }

  # Allow assuming the Terraform state backend role (needed to read state)
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [var.tf_access_role_arn]
  }

  # Allow EC2 DescribeRegions - required by many Terraform modules for region validation
  statement {
    sid    = "EC2DescribeRegions"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

# Terraform Apply Access - Read/write state access, admin account access
data "aws_iam_policy_document" "terraform_apply_access" {
  count = local.tf_access_enabled ? 1 : 0

  statement {
    sid    = "TerraformStateBackendS3Bucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [var.tf_access_bucket_arn, "${var.tf_access_bucket_arn}/*"]
  }

  # Only add the DynamoDB table statement if the DynamoDB table ARN is set.
  # You may not have created a DynamoDB table if you're using S3 state locking
  dynamic "statement" {
    for_each = (local.tf_access_enabled && var.tf_access_dynamodb_table_arn != "") ? [1] : []

    content {
      sid       = "TerraformStateBackendDynamoDbTable"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [var.tf_access_dynamodb_table_arn]
    }
  }

  # Allow assuming the Terraform state backend role
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [var.tf_access_role_arn]
  }

  # Allow EC2 DescribeRegions - required by many Terraform modules for region validation
  statement {
    sid    = "EC2DescribeRegions"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

# Terraform State Access - Read/write state access only (no account permissions)
data "aws_iam_policy_document" "terraform_state_access" {
  count = local.tf_access_enabled ? 1 : 0

  # Read/write access to Terraform state S3 bucket
  statement {
    sid    = "TerraformStateBackendS3Bucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [var.tf_access_bucket_arn, "${var.tf_access_bucket_arn}/*"]
  }

  # DynamoDB table access for state locking (if configured)
  dynamic "statement" {
    for_each = (local.tf_access_enabled && var.tf_access_dynamodb_table_arn != "") ? [1] : []

    content {
      sid       = "TerraformStateBackendDynamoDbTable"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [var.tf_access_dynamodb_table_arn]
    }
  }

  # Allow assuming the Terraform state backend role
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [var.tf_access_role_arn]
  }
}

# Additional backends policy documents

# Terraform Plan Access - Read-only state access for additional backends
data "aws_iam_policy_document" "terraform_plan_access_additional" {
  for_each = local.tf_access_additional_backends_enabled ? var.tf_access_additional_backends : {}

  # Read-only access to Terraform state S3 bucket
  statement {
    sid    = "TerraformStateBackendS3BucketReadOnly"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [each.value.bucket_arn, "${each.value.bucket_arn}/*"]
  }

  # Allow assuming the Terraform state backend role
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [each.value.role_arn]
  }

  # Allow EC2 DescribeRegions - required by many Terraform modules for region validation
  statement {
    sid    = "EC2DescribeRegions"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

# Terraform Apply Access - Read/write state access for additional backends
data "aws_iam_policy_document" "terraform_apply_access_additional" {
  for_each = local.tf_access_additional_backends_enabled ? var.tf_access_additional_backends : {}

  statement {
    sid    = "TerraformStateBackendS3Bucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [each.value.bucket_arn, "${each.value.bucket_arn}/*"]
  }

  # Conditional DynamoDB access (only if table ARN is provided)
  dynamic "statement" {
    for_each = each.value.dynamodb_table_arn != "" ? [1] : []

    content {
      sid       = "TerraformStateBackendDynamoDbTable"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [each.value.dynamodb_table_arn]
    }
  }

  # Allow assuming the Terraform state backend role
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [each.value.role_arn]
  }

  # Allow EC2 DescribeRegions - required by many Terraform modules for region validation
  statement {
    sid    = "EC2DescribeRegions"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

# Terraform State Access - Read/write state only for additional backends
data "aws_iam_policy_document" "terraform_state_access_additional" {
  for_each = local.tf_access_additional_backends_enabled ? var.tf_access_additional_backends : {}

  # Read/write access to Terraform state S3 bucket
  statement {
    sid    = "TerraformStateBackendS3Bucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [each.value.bucket_arn, "${each.value.bucket_arn}/*"]
  }

  # DynamoDB table access for state locking (if configured)
  dynamic "statement" {
    for_each = each.value.dynamodb_table_arn != "" ? [1] : []

    content {
      sid       = "TerraformStateBackendDynamoDbTable"
      effect    = "Allow"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [each.value.dynamodb_table_arn]
    }
  }

  # Allow assuming the Terraform state backend role
  statement {
    sid    = "TerraformStateBackendAssumeRole"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]
    resources = [each.value.role_arn]
  }
}
