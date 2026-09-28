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

  # HIGH fix (round-2 review): ec2:DeleteVolume must also be ARN-scoped to
  # the volume resource type, not just Resource "*" -- ec2:DeleteVolume DOES
  # support resource-level ARN scoping (see the AWS "Resource-level
  # permissions for EC2 API actions" reference).
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Action == "ec2:DeleteVolume"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Effect == "Allow"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Resource == "arn:aws:ec2:eu-west-2:123456789012:volume/*"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DeleteOnlyEbsVolumesTaggedByThisTest"]).Condition == {
        StringEquals = { "aws:ResourceTag/BackupRestoreTest" = "true" }
      }
    )
    error_message = "ec2:DeleteVolume must be ARN-scoped to the EC2 volume resource type AND allowed only on volumes already tagged BackupRestoreTest=true (aws:ResourceTag)."
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

  # HIGH fix: ec2:CreateTags DOES support resource-level ARN scoping to the
  # volume resource type, so it is ARN-scoped AND additionally requires the
  # target to carry no Environment tag yet (Null = "true"), which every
  # Terraform-managed volume already has via default_tags (round-2 review:
  # the Null condition alone is not sufficient -- see
  # deny_blocks_csi_managed_ebs_volumes below for the CSI-managed-volume
  # gap it does not cover).
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"]).Action == "ec2:CreateTags"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"]).Resource == "arn:aws:ec2:eu-west-2:123456789012:volume/*"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"]).Condition == {
        StringEquals = { "aws:RequestTag/BackupRestoreTest" = "true" }
        Null         = { "aws:ResourceTag/Environment" = "true" }
      }
    )
    error_message = "ec2:CreateTags must be ARN-scoped to the EC2 volume resource type AND require both the aws:RequestTag marker and the absence of an existing Environment tag on the target."
  }
}

run "deny_blocks_csi_managed_ebs_volumes" {
  command = plan

  # HIGH fix (round-2 review): the Null-Environment-tag condition above does
  # not protect EBS volumes the eks-addons aws-ebs-csi-driver addon
  # provisions for Kubernetes PersistentVolumes -- those never carry an
  # Environment tag (the CSI driver creates them via its own AWS API calls,
  # not this repo's Terraform) but ARE real, in-use application data. A
  # third explicit Deny keyed on the CSI driver's own unconditional
  # ownership tag ("ebs.csi.aws.com/cluster") closes that gap.
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DenyTaggingOrDeletingCsiManagedEbsVolumes"]).Effect == "Deny"
      && toset(flatten([one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DenyTaggingOrDeletingCsiManagedEbsVolumes"]).Action])) == toset(["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DenyTaggingOrDeletingCsiManagedEbsVolumes"]).Condition == {
        Null = { "aws:ResourceTag/ebs.csi.aws.com/cluster" = "false" }
      }
    )
    error_message = "A Deny statement must block all four tag/delete actions on any resource carrying the ebs.csi.aws.com/cluster tag (the AWS EBS CSI driver's own unconditional ownership tag)."
  }
}

run "explicit_deny_blocks_environment_managed_and_backup_opted_in_resources" {
  command = plan

  # HIGH fix backstop: explicit Deny statements that hold even if the Allow
  # scoping above is ever loosened by mistake. Three, as of the round-2
  # review fix: Environment-tag-exists, Backup=true, and
  # CSI-managed-volume-tag-exists (see deny_blocks_csi_managed_ebs_volumes).
  assert {
    condition = length([
      for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s
      if s.Effect == "Deny" && toset(flatten([s.Action])) == toset(["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"])
    ]) == 3
    error_message = "There must be three explicit Deny statements (Environment-tag-exists, Backup=true, and CSI-managed-volume-tag-exists) covering all four tag/delete actions."
  }
}

run "backup_actions_are_scoped_to_this_components_own_vault" {
  command = plan

  # HIGH fix (independent review of the master merge): per the AWS Backup IAM
  # Service Authorization reference, only backup:ListRecoveryPointsByBackupVault
  # actually authorizes against the backupVault resource type.
  # backup:StartRestoreJob and backup:GetRecoveryPointRestoreMetadata
  # authorize against the recoveryPoint* resource type (the underlying EC2 or
  # RDS snapshot ARN), and backup:DescribeRestoreJob has no resource type at
  # all. Scoping all four to the vault ARN made StartRestoreJob and
  # GetRecoveryPointRestoreMetadata AccessDenied at runtime.
  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "ListRecoveryPointsInOwnVault"]).Action == "backup:ListRecoveryPointsByBackupVault"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "ListRecoveryPointsInOwnVault"]).Resource == "arn:aws:backup:eu-west-2:123456789012:backup-vault:test-backup"
    )
    error_message = "backup:ListRecoveryPointsByBackupVault must be scoped to this component's own vault ARN, not '*'."
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "StartRestoreAndGetMetadataForOwnEnvironmentRecoveryPoints"]).Action) == toset(["backup:StartRestoreJob", "backup:GetRecoveryPointRestoreMetadata"])
      && toset(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "StartRestoreAndGetMetadataForOwnEnvironmentRecoveryPoints"]).Resource) == toset([
        "arn:aws:ec2:eu-west-2::snapshot/*",
        "arn:aws:rds:eu-west-2:123456789012:snapshot:awsbackup:*",
        "arn:aws:backup:eu-west-2:123456789012:recovery-point:*",
      ])
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "StartRestoreAndGetMetadataForOwnEnvironmentRecoveryPoints"]).Condition == {
        StringEquals = { "aws:ResourceTag/Environment" = "test" }
      }
    )
    error_message = "backup:StartRestoreJob and backup:GetRecoveryPointRestoreMetadata must be scoped to the recovery-point/snapshot resource types, not the vault ARN, and must require the recovery point's own Environment tag."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DescribeAnyRestoreJob"]).Action == "backup:DescribeRestoreJob"
      && one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DescribeAnyRestoreJob"]).Resource == "*"
      && !contains(keys(one([for s in jsondecode(aws_iam_role_policy.backup_testing_custom[0].policy).Statement : s if try(s.Sid, "") == "DescribeAnyRestoreJob"])), "Condition")
    )
    error_message = "backup:DescribeRestoreJob has no resource-level permissions in the AWS Backup IAM reference and must be Resource \"*\"."
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

# HIGH fix (round-5 review): dev sets monthly_retention_days = 30 and
# staging sets monthly_retention_days = 90, and neither overrides
# monthly_cold_storage_days, so both used to inherit the variable's old
# default of 90. AWS Backup requires delete_after >= cold_storage_after + 90
# (a recovery point must stay in cold storage at least 90 days before it can
# be deleted), so both combinations would reject aws_backup_plan.main at
# apply time with InvalidParameterValueException -- after the plan sweep,
# and every other check, already passed. This reproduces that exact
# combination directly against the resource's new lifecycle precondition.
run "monthly_retention_shorter_than_cold_storage_plus_90_days_fails_plan" {
  command = plan

  variables {
    monthly_retention_days    = 30
    monthly_cold_storage_days = 90
  }

  expect_failures = [aws_backup_plan.main]
}

# The catalog fix for the above (stacks/catalog/backup/defaults.yaml sets
# monthly_cold_storage_days: null; only the prod instance turns it back on
# at 90, alongside its 2555-day retention) resolves to these two valid
# combinations. Asserts they plan cleanly, i.e. the precondition does not
# reject a stack that already fixed the mismatch.
run "dev_and_staging_resolved_monthly_retention_and_cold_storage_are_valid" {
  command = plan

  variables {
    daily_retention_days      = 7
    weekly_retention_days     = 14
    monthly_retention_days    = 30
    monthly_cold_storage_days = null
  }

  assert {
    condition     = length(aws_backup_plan.main.rule) == 3
    error_message = "dev's resolved retention/cold-storage combination (monthly_retention_days = 30, monthly_cold_storage_days = null) must plan cleanly."
  }
}

run "staging_resolved_monthly_retention_and_cold_storage_are_valid" {
  command = plan

  variables {
    daily_retention_days      = 14
    weekly_retention_days     = 30
    monthly_retention_days    = 90
    monthly_cold_storage_days = null
  }

  assert {
    condition     = length(aws_backup_plan.main.rule) == 3
    error_message = "staging's resolved retention/cold-storage combination (monthly_retention_days = 90, monthly_cold_storage_days = null) must plan cleanly."
  }
}

# monthly_cold_storage_days now defaults to null (matching
# daily_cold_storage_days/weekly_cold_storage_days and
# cloudposse/terraform-aws-backup's rules[].lifecycle.cold_storage_after,
# unset unless a caller opts in). No override here at all -- this exercises
# the component's own bare default, not a catalog-supplied value -- and
# asserts the monthly rule's lifecycle has no cold storage transition.
run "monthly_cold_storage_default_is_null_no_transition" {
  command = plan

  assert {
    condition     = var.monthly_cold_storage_days == null
    error_message = "monthly_cold_storage_days must default to null."
  }

  assert {
    condition     = [for r in aws_backup_plan.main.rule : r.lifecycle[0].cold_storage_after if r.rule_name == "monthly-backup"][0] == null
    error_message = "With monthly_cold_storage_days left at its default (null), the monthly rule's lifecycle.cold_storage_after must be null: no cold storage transition."
  }
}

# An instance that explicitly opts into cold storage (e.g. prod's
# monthly_cold_storage_days = 90 in security.yaml) with a retention long
# enough to satisfy delete_after >= cold_storage_after + 90 gets an actual
# transition, and the precondition passes rather than rejecting the plan.
run "monthly_cold_storage_days_explicit_90_sets_transition" {
  command = plan

  variables {
    monthly_retention_days    = 365
    monthly_cold_storage_days = 90
  }

  assert {
    condition     = [for r in aws_backup_plan.main.rule : r.lifecycle[0].cold_storage_after if r.rule_name == "monthly-backup"][0] == 90
    error_message = "With monthly_cold_storage_days = 90 and monthly_retention_days = 365 (>= 90 + 90), the monthly rule's lifecycle.cold_storage_after must be 90."
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

run "rds_tag_based_selection_excludes_read_replicas" {
  command = plan

  variables {
    enable_rds_backup = true
  }

  # MEDIUM fix (round-2 review), corrected in round-3: rds/main and rds/data
  # set Backup=true on their own var.tags, which reaches a
  # create_read_replica = true instance's read replica too. AWS Backup's
  # handling of RDS read replicas is restricted, so a string_not_equals
  # condition on aws:ResourceTag/Role = "read-replica" (rds/main.tf's
  # aws_db_instance.read_replica tags itself that way) excludes it,
  # regardless of which rds/* instance created it. The round-2 fix used
  # not_resources with a leading-wildcard ARN pattern, which the
  # BackupSelection API does not support (a wildcard may only appear at the
  # end of an ARN pattern), so it is replaced by this tag condition.
  assert {
    condition = anytrue([
      for c in one(aws_backup_selection.rds_tagged_daily[0].condition).string_not_equals :
      c.key == "aws:ResourceTag/Role" && c.value == "read-replica"
    ])
    error_message = "enable_rds_backup's tag-based selection must exclude RDS read replicas via a string_not_equals condition on aws:ResourceTag/Role."
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

run "backup_testing_lambda_has_its_own_encrypted_log_group" {
  command = plan

  # LOW fix: without an explicit log group, Lambda auto-creates
  # /aws/lambda/<name> with no retention and no CMK encryption, against this
  # repo's encrypt-at-rest convention. Set kms_key_arn explicitly so this run
  # actually proves the log group is wired to it, not just that kms_key_id is
  # null when the variable is unset.
  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition = (
      length(aws_cloudwatch_log_group.backup_testing) == 1
      && aws_cloudwatch_log_group.backup_testing[0].name == "/aws/lambda/test-backup-testing"
      && aws_cloudwatch_log_group.backup_testing[0].retention_in_days == 365
      && aws_cloudwatch_log_group.backup_testing[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    )
    error_message = "The restore-test Lambda's CloudWatch log group must use var.kms_key_arn for encryption, not be left on the default/unencrypted path."
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
