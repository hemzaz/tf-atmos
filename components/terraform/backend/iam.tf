/*
 * State access roles, modelled on the `access_roles` of Cloud Posse's
 * aws-tfstate-backend component (cloudposse-terraform-components/aws-tfstate-backend,
 * src/iam.tf): one IAM role per map entry, each with an S3 policy that adds
 * Put/Delete only when `write_enabled`, and a trust policy that names the
 * allowed principals by ARN in an `aws:PrincipalArn` condition.
 *
 * As upstream, the trust policy's `principals` are the account roots of those
 * ARNs and the condition does the narrowing. That is what lets the backend
 * trust roles that do not exist yet (the CI roles of iam/ci are created
 * after this component, and a role named directly as a principal must exist
 * when the trust policy is written). The condition uses ArnEquals rather than
 * upstream's ArnLike because allowed_principal_arns may not contain wildcards.
 *
 * Also as upstream, the principal running Terraform is always allowed
 * (`caller_arn` below): the administrator who bootstraps this component must
 * be able to assume the write role to migrate its state into the bucket and
 * to manage it afterwards. The aws_iam_session_context data source turns an
 * assumed-role session ARN into its role ARN, path included (upstream uses
 * awsutils' eks_role_arn, which drops the path). A root-user caller is never
 * added. An entry with no allowed_principal_arns (upstream's default) is
 * therefore trusted by the caller alone: that is the core_write role, the
 * only one that can write the backend's own (fnx-core-root) state.
 *
 * KMS: the state key's policy delegates to IAM (account root only), so the
 * roles' own policies grant key use. Read: Decrypt. Write: also Encrypt and
 * GenerateDataKey, which S3 needs to write SSE-KMS objects.
 */

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  caller_arn = endswith(data.aws_iam_session_context.current.issuer_arn, ":root") ? null : data.aws_iam_session_context.current.issuer_arn

  access_role_principal_arns = {
    for key, role in var.access_roles : key => sort(distinct(compact(concat(role.allowed_principal_arns, [local.caller_arn]))))
  }

  # arn:<partition>:iam::<account>:root for every account an allowed principal lives in
  access_role_principal_accounts = {
    for key, arns in local.access_role_principal_arns : key => sort(distinct([
      for arn in arns : format("arn:%s:iam::%s:root", regex("^arn:([^:]+):iam::([0-9]{12}):", arn)...)
    ]))
  }
}

data "aws_iam_policy_document" "access_role_assume" {
  for_each = var.access_roles

  statement {
    sid     = "AllowNamedPrincipals"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:SetSourceIdentity", "sts:TagSession"]

    # Any principal in these accounts, narrowed to exactly the allowed ARNs below
    principals {
      type        = "AWS"
      identifiers = local.access_role_principal_accounts[each.key]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = local.access_role_principal_arns[each.key]
    }
  }
}

resource "aws_iam_role" "access" {
  for_each = var.access_roles

  name               = each.value.role_name
  description        = "${each.value.write_enabled ? "Read/write" : "Read-only"} access to the Terraform state in ${var.bucket_name}"
  assume_role_policy = data.aws_iam_policy_document.access_role_assume[each.key].json

  lifecycle {
    # An empty allowed_principal_arns trusts only the caller (the core_write
    # role), and a root-user caller is never added: that would leave a trust
    # policy with no principal at all.
    precondition {
      condition     = length(local.access_role_principal_arns[each.key]) > 0
      error_message = "access_roles[\"${each.key}\"] would trust nobody: allowed_principal_arns is empty and the caller is the account root user. Apply as an IAM role/user, or list a principal."
    }
  }
}

# State read (plus write and S3-native lock files "<key>.tflock" when write_enabled)
data "aws_iam_policy_document" "access_role" {
  for_each = var.access_roles

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  # Read-only roles only: what the disaster-recovery checks (workflows/scripts/dr,
  # run with the CI plan roles) read through them. recover-state lists state
  # object VERSIONS to pick one to restore (ListBucketVersions; names and version
  # IDs only - GetObjectVersion is not granted); dr-status reads the bucket's
  # versioning and replication settings. Like ListBucket, bucket-level: the key
  # layout puts the component first, so no per-stage s3:prefix exists.
  dynamic "statement" {
    for_each = each.value.write_enabled ? [] : [true]

    content {
      sid       = "DisasterRecoveryChecks"
      effect    = "Allow"
      actions   = ["s3:ListBucketVersions", "s3:GetBucketVersioning", "s3:GetReplicationConfiguration"]
      resources = [aws_s3_bucket.terraform_state.arn]
    }
  }

  # Object access is limited to object_key_patterns: every role is split by
  # stage (non-prod / prod / core) within the one bucket. ListBucket above is not
  # prefix-scoped: Terraform's S3 backend lists "<workspace_key_prefix>/" (the
  # component, shared by every stack's workspaces) to find workspaces, so a
  # role can see key NAMES across stacks, never object contents.
  statement {
    sid       = each.value.write_enabled ? "ReadWriteStateAndLockFiles" : "ReadState"
    effect    = "Allow"
    actions   = concat(["s3:GetObject"], each.value.write_enabled ? ["s3:PutObject", "s3:DeleteObject"] : [])
    resources = [for pattern in each.value.object_key_patterns : "${aws_s3_bucket.terraform_state.arn}/${pattern}"]
  }

  statement {
    sid       = "UseStateKey"
    effect    = "Allow"
    actions   = concat(["kms:Decrypt", "kms:DescribeKey"], each.value.write_enabled ? ["kms:Encrypt", "kms:GenerateDataKey"] : [])
    resources = [aws_kms_key.terraform_state_key.arn]
  }
}

resource "aws_iam_role_policy" "access" {
  for_each = var.access_roles

  name   = "TerraformStateAccess"
  role   = aws_iam_role.access[each.key].id
  policy = data.aws_iam_policy_document.access_role[each.key].json
}
