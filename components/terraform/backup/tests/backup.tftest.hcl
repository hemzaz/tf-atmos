# Offline tests for the restore-test Lambda's IAM policy (M11): every
# destructive action must carry the BackupRestoreTest tag condition, and none
# may grant a destructive/creation action on Resource "*" with no condition.
# Real AWS provider, dummy credentials, override_data for caller identity --
# as in components/terraform/s3/tests and components/terraform/kms/tests.
# The policy is jsonencode()'d directly on the resource (not through
# aws_iam_policy_document), so `command = plan` is enough: local.backup_vault_arn
# and local.backup_service_role_arn are built from known values (region,
# account id, and the vault/role's own `name` argument), not from their
# computed `.arn` attributes, so the whole policy JSON is known at plan time.
# All runs are plans; nothing reaches AWS.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

# provider.tf's `replica` alias falls back to var.region when
# enable_cross_region_backup is off, but the alias still needs its own dummy
# credentials configured here.
provider "aws" {
  alias                       = "replica"
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  enable_backup_testing = true
}

run "no_unconditioned_destructive_or_creation_actions" {
  command = plan

  # M11: no statement may allow a Delete*/Create*/Restore* action on Resource
  # "*" without a Condition block scoping it.
  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement :
      statement.Effect != "Allow" || statement.Resource != "*" || contains(keys(statement), "Condition") || !anytrue([
        for action in flatten([statement.Action]) :
        strcontains(action, ":Delete") || strcontains(action, ":Create") || strcontains(action, ":Restore")
      ])
    ])
    error_message = "Every Allow statement with Resource = \"*\" that grants a Delete/Create/Restore action must carry a Condition block."
  }
}

run "delete_actions_require_the_restore_test_resource_tag" {
  command = plan

  assert {
    condition = (
      toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyResourcesTaggedByThisTest"]).Action) == toset(["ec2:DeleteVolume", "rds:DeleteDBInstance"])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyResourcesTaggedByThisTest"]).Effect == "Allow"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyResourcesTaggedByThisTest"]).Condition == {
        StringEquals = { "aws:ResourceTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "ec2:DeleteVolume and rds:DeleteDBInstance must be allowed only on resources already tagged BackupRestoreTest=true (aws:ResourceTag)."
  }
}

run "tagging_actions_require_the_restore_test_tag_on_the_request" {
  command = plan

  assert {
    condition = (
      toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredResourcesOnlyWithTheTestTag"]).Action) == toset(["ec2:CreateTags", "rds:AddTagsToResource"])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredResourcesOnlyWithTheTestTag"]).Condition == {
        StringEquals = { "aws:RequestTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "ec2:CreateTags and rds:AddTagsToResource must require the request itself carry BackupRestoreTest=true (aws:RequestTag)."
  }
}

run "backup_actions_are_scoped_to_this_components_own_vault" {
  command = plan

  assert {
    condition = (
      toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "BackupVaultReadAndRestore"]).Action) == toset(["backup:ListRecoveryPointsByBackupVault", "backup:StartRestoreJob", "backup:DescribeRestoreJob"])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "BackupVaultReadAndRestore"]).Resource == "arn:aws:backup:eu-west-2:123456789012:backup-vault:test-backup"
    )
    error_message = "backup:* read/restore actions must be scoped to this component's own vault ARN, not '*'."
  }
}

run "pass_role_is_scoped_to_the_backup_service_role_and_service" {
  command = plan

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "PassBackupServiceRoleForRestore"]).Action == "iam:PassRole"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "PassBackupServiceRoleForRestore"]).Resource == "arn:aws:iam::123456789012:role/test-backup-service-role"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "PassBackupServiceRoleForRestore"]).Condition == {
        StringEquals = { "iam:PassedToService" = "backup.amazonaws.com" }
      }
    )
    error_message = "iam:PassRole must be limited to the backup service role, and to it being passed to backup.amazonaws.com only."
  }
}

run "no_legacy_unconditioned_ec2_or_rds_create_restore_grants" {
  command = plan

  # The old policy granted ec2:CreateVolume and rds:RestoreDBInstanceFromDBSnapshot
  # directly to this Lambda role; the restore now happens under the passed
  # backup service role instead (see PassBackupServiceRoleForRestore), so
  # neither action should appear anywhere in this policy.
  assert {
    condition = length([
      for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s
      if anytrue([for action in flatten([s.Action]) : contains(["ec2:CreateVolume", "rds:RestoreDBInstanceFromDBSnapshot"], action)])
    ]) == 0
    error_message = "This Lambda's own role must not grant ec2:CreateVolume or rds:RestoreDBInstanceFromDBSnapshot: AWS Backup performs the restore itself under the passed backup service role."
  }
}

run "rds_tag_based_selection_is_scoped_to_this_environment" {
  command = plan

  variables {
    enable_rds_backup = true
  }

  assert {
    condition = (
      length(aws_backup_selection.rds_tagged_daily) == 1
      && one([for t in aws_backup_selection.rds_tagged_daily[0].selection_tag : t if t.key == "Backup"]).value == "true"
      && one([for t in aws_backup_selection.rds_tagged_daily[0].selection_tag : t if t.key == "Environment"]).value == "test"
    )
    error_message = "enable_rds_backup must select RDS instances by Backup=true and Environment=<var.tags.Environment> tags, not by reading rds state."
  }
}

run "no_rds_tag_selection_by_default" {
  command = plan

  assert {
    condition     = length(aws_backup_selection.rds_tagged_daily) == 0
    error_message = "Tag-based RDS selection is opt-in via enable_rds_backup."
  }
}
