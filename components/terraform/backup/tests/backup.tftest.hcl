# Offline tests for the restore-test Lambda's IAM policy (M11, and its later
# hardening) and for the tag-based backup selections (CRITICAL/HIGH fixes).
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

  # M11: no Allow statement may grant a Delete*/Create*/Restore* action on
  # Resource "*" without a Condition block scoping it.
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

run "ebs_delete_requires_the_restore_test_resource_tag" {
  command = plan

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Action == "ec2:DeleteVolume"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Effect == "Allow"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Condition == {
        StringEquals = { "aws:ResourceTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "ec2:DeleteVolume must be allowed only on volumes already tagged BackupRestoreTest=true (aws:ResourceTag)."
  }
}

run "rds_delete_is_scoped_to_the_restore_test_db_prefix_and_tag" {
  command = plan

  # HIGH fix: rds:DeleteDBInstance must be scoped by Resource ARN to the
  # fixed restore-test prefix, not just by the aws:ResourceTag condition --
  # otherwise a bug that tags the wrong ARN could still reach a real database.
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyRdsInstancesUnderTheRestoreTestPrefix"]).Action == "rds:DeleteDBInstance"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyRdsInstancesUnderTheRestoreTestPrefix"]).Resource == "arn:aws:rds:eu-west-2:123456789012:db:test-backup-restore-test-*"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyRdsInstancesUnderTheRestoreTestPrefix"]).Condition == {
        StringEquals = { "aws:ResourceTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "rds:DeleteDBInstance must be scoped to the restore-test DB identifier prefix's ARN pattern AND require the aws:ResourceTag condition."
  }
}

run "rds_tagging_is_scoped_to_the_restore_test_db_prefix" {
  command = plan

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredRdsInstancesOnlyUnderTheRestoreTestPrefix"]).Action == "rds:AddTagsToResource"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredRdsInstancesOnlyUnderTheRestoreTestPrefix"]).Resource == "arn:aws:rds:eu-west-2:123456789012:db:test-backup-restore-test-*"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredRdsInstancesOnlyUnderTheRestoreTestPrefix"]).Condition == {
        StringEquals = { "aws:RequestTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "rds:AddTagsToResource must be scoped to the restore-test DB identifier prefix's ARN pattern AND require the aws:RequestTag condition."
  }
}

run "ebs_tagging_requires_the_request_tag_and_no_existing_environment_tag" {
  command = plan

  # HIGH fix: ec2:CreateTags can't be ARN-scoped, so it is scoped instead by
  # requiring the target to carry no Environment tag yet (Null = "true"),
  # which every Terraform-managed volume already has via default_tags.
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"]).Action == "ec2:CreateTags"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"]).Condition == {
        StringEquals = { "aws:RequestTag/BackupRestoreTest" = "true" }
        Null         = { "aws:ResourceTag/Environment" = "true" }
      }
    )
    error_message = "ec2:CreateTags must require both the aws:RequestTag marker and the absence of an existing Environment tag on the target."
  }
}

run "explicit_deny_blocks_environment_managed_and_backup_opted_in_resources" {
  command = plan

  # HIGH fix backstop: an explicit Deny that holds even if either Allow
  # scoping above is ever loosened by mistake.
  assert {
    condition = length([
      for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s
      if s.Effect == "Deny" && toset(flatten([s.Action])) == toset(["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"])
    ]) == 2
    error_message = "There must be two explicit Deny statements (Environment-tag-exists, and Backup=true) covering all four tag/delete actions."
  }
}

run "backup_actions_are_scoped_to_this_components_own_vault" {
  command = plan

  assert {
    condition = (
      toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "BackupVaultReadAndRestore"]).Action) == toset(["backup:ListRecoveryPointsByBackupVault", "backup:StartRestoreJob", "backup:DescribeRestoreJob", "backup:GetRecoveryPointRestoreMetadata"])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "BackupVaultReadAndRestore"]).Resource == "arn:aws:backup:eu-west-2:123456789012:backup-vault:test-backup"
    )
    error_message = "backup:* read/restore/metadata actions must be scoped to this component's own vault ARN, not '*'."
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

run "backup_plan_has_a_daily_weekly_and_monthly_rule" {
  command = plan

  # HIGH fix: previously three separate plans existed, each with one rule,
  # but every selection pointed only at the daily plan, so the weekly/monthly
  # rules never backed anything up. Now there is one plan with all three
  # rules, so any selection attached to it is covered by all three.
  assert {
    condition     = length(aws_backup_plan.main.rule) == 3
    error_message = "The backup plan must have exactly one rule each for daily, weekly and monthly cadences."
  }

  assert {
    condition     = toset([for r in aws_backup_plan.main.rule : r.rule_name]) == toset(["daily-backup", "weekly-backup", "monthly-backup"])
    error_message = "The backup plan's three rules must be named daily-backup, weekly-backup and monthly-backup."
  }
}

run "rds_tag_based_selection_is_and_scoped_to_rds_and_this_environment" {
  command = plan

  variables {
    enable_rds_backup = true
  }

  # CRITICAL fix: this used to be two `selection_tag` blocks (Backup=true,
  # Environment=<env>), which AWS Backup's ListOfTags combines with OR --
  # selecting every RDS instance with EITHER tag, i.e. every RDS instance in
  # the account (Environment is always set via default_tags). `resources`
  # (RDS-only) plus a `condition` block ANDs both tags instead.
  assert {
    condition = (
      length(aws_backup_selection.rds_tagged_daily) == 1
      && toset(aws_backup_selection.rds_tagged_daily[0].resources) == toset(["arn:aws:rds:eu-west-2:123456789012:db:*"])
      && length(aws_backup_selection.rds_tagged_daily[0].selection_tag) == 0
      && length(aws_backup_selection.rds_tagged_daily[0].condition) == 1
    )
    error_message = "enable_rds_backup must select RDS instances (resources scoped to the rds ARN pattern) via a condition block, not selection_tag entries."
  }

  assert {
    condition = (
      toset([for c in one(aws_backup_selection.rds_tagged_daily[0].condition).string_equals : c.key]) == toset(["aws:ResourceTag/Backup", "aws:ResourceTag/Environment"])
      && one([for c in one(aws_backup_selection.rds_tagged_daily[0].condition).string_equals : c if c.key == "aws:ResourceTag/Backup"]).value == "true"
      && one([for c in one(aws_backup_selection.rds_tagged_daily[0].condition).string_equals : c if c.key == "aws:ResourceTag/Environment"]).value == "test"
    )
    error_message = "The RDS tag-based selection's condition block must AND Backup=true with Environment=<var.tags.Environment>."
  }
}

run "no_rds_tag_selection_by_default" {
  command = plan

  assert {
    condition     = length(aws_backup_selection.rds_tagged_daily) == 0
    error_message = "Tag-based RDS selection is opt-in via enable_rds_backup."
  }
}

run "ec2_and_ebs_tag_based_selections_are_and_scoped_by_resource_type" {
  command = plan

  variables {
    enable_ec2_backup = true
    enable_ebs_backup = true
  }

  assert {
    condition = (
      length(aws_backup_selection.ec2_daily) == 1
      && toset(aws_backup_selection.ec2_daily[0].resources) == toset(["arn:aws:ec2:eu-west-2:123456789012:instance/*"])
      && length(aws_backup_selection.ec2_daily[0].selection_tag) == 0
      && length(aws_backup_selection.ec2_daily[0].condition) == 1
    )
    error_message = "enable_ec2_backup must select EC2 instances (resources scoped to the ec2 instance ARN pattern) via a condition block, not selection_tag."
  }

  assert {
    condition = (
      length(aws_backup_selection.ebs_tagged_daily) == 1
      && toset(aws_backup_selection.ebs_tagged_daily[0].resources) == toset(["arn:aws:ec2:eu-west-2:123456789012:volume/*"])
      && length(aws_backup_selection.ebs_tagged_daily[0].selection_tag) == 0
      && length(aws_backup_selection.ebs_tagged_daily[0].condition) == 1
    )
    error_message = "enable_ebs_backup must select EBS volumes (resources scoped to the ec2 volume ARN pattern) via a condition block, not selection_tag, and must also require the Environment tag."
  }
}

run "explicit_arn_list_selections_are_built" {
  command = plan

  variables {
    rds_instances  = ["mydb"]
    ebs_volume_ids = ["vol-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_backup_selection.rds_daily) == 1 && toset(aws_backup_selection.rds_daily[0].resources) == toset(["arn:aws:rds:eu-west-2:123456789012:db:mydb"])
    error_message = "The explicit RDS ARN-list selection must build its resources list from var.rds_instances."
  }

  assert {
    condition     = length(aws_backup_selection.ebs_daily) == 1 && toset(aws_backup_selection.ebs_daily[0].resources) == toset(["arn:aws:ec2:eu-west-2:123456789012:volume/vol-0123456789abcdef0"])
    error_message = "The explicit EBS ARN-list selection must build its resources list from var.ebs_volume_ids."
  }
}

run "no_explicit_arn_list_selections_by_default" {
  command = plan

  assert {
    condition     = length(aws_backup_selection.rds_daily) == 0 && length(aws_backup_selection.ebs_daily) == 0
    error_message = "Explicit ARN-list selections must not be created when their list variables are empty."
  }
}

run "backup_notifications_topic_has_a_publish_policy" {
  command = plan

  # HIGH fix: aws_backup_vault_notifications alone does not let AWS Backup
  # (or the CloudWatch alarms publishing to the same topic) actually publish
  # -- the topic needs an access policy statement granting SNS:Publish.
  assert {
    condition = (
      length(aws_sns_topic_policy.backup_notifications) == 1
      && length([
        for s in jsondecode(aws_sns_topic_policy.backup_notifications[0].policy).Statement : s
        if s.Effect == "Allow" && try(s.Principal.Service, "") == "backup.amazonaws.com" && s.Action == "SNS:Publish"
      ]) == 1
      && length([
        for s in jsondecode(aws_sns_topic_policy.backup_notifications[0].policy).Statement : s
        if s.Effect == "Allow" && try(s.Principal.Service, "") == "cloudwatch.amazonaws.com" && s.Action == "SNS:Publish"
      ]) == 1
    )
    error_message = "The backup notifications topic must have a policy allowing backup.amazonaws.com and cloudwatch.amazonaws.com to publish."
  }
}

run "no_backup_notifications_topic_policy_when_notifications_disabled" {
  command = plan

  variables {
    enable_backup_notifications = false
  }

  assert {
    condition     = length(aws_sns_topic_policy.backup_notifications) == 0
    error_message = "The SNS topic policy is opt-in via enable_backup_notifications, same as the topic itself."
  }
}
