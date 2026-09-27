"""
AWS Backup restore-test Lambda function.

Runs a scheduled, end-to-end restore test against the most recent completed
recovery point in the backup vault: it starts a restore job (using the
backup service role, which already carries
AWSBackupServiceRolePolicyForRestores), tags the resource the restore job
creates with the BackupRestoreTest marker tag, validates the restored
resource came up healthy, and finally deletes it.

This function's own IAM role (aws_iam_role.backup_testing / the
aws_iam_role_policy.backup_testing_custom policy in main.tf) can delete a
resource ONLY when it already carries that marker tag (an aws:ResourceTag
condition on ec2:DeleteVolume/rds:DeleteDBInstance), and can apply the tag
itself only via a request that sets that exact tag (an aws:RequestTag
condition on ec2:CreateTags/rds:AddTagsToResource). Beyond that, RDS
tagging/deletion is further scoped by ARN to the fixed
RDS_RESTORE_TEST_DB_PREFIX this function itself names every restore-test
instance under, and two explicit Denies block all four of
ec2:CreateTags/ec2:DeleteVolume/rds:AddTagsToResource/rds:DeleteDBInstance
outright on any resource that already carries an Environment tag or a
Backup=true tag, as a backstop over both the EC2 and RDS Allow grants. Every
Terraform-managed resource in this repo carries Environment via provider
default_tags, and AWS Backup's StartRestoreJob does not copy a recovery
point's tags onto the resource it restores unless the caller passes
CopySourceTagsToRestoredResource=True (this function never does), so a
freshly restored volume or DB instance carries neither tag until this code
tags it itself. So a bug in this code that passes the wrong ARN into
_tag_restored_resource/_delete_restored_resource still cannot reach a real,
managed volume or database -- not just an untagged one (this is the M11
finding, and its later hardening, that this function's IAM policy fixes).

Known limitation: RESTORE_JOB_TIMEOUT_SECONDS leaves headroom under this
Lambda's own 900s timeout, but a real RDS restore (as opposed to this EBS-
sized default) commonly takes longer than that -- and AWS Lambda's hard
15-minute cap means no single synchronous invocation can safely poll a slow
RDS restore to completion. If the poll in _restore_and_wait times out, the
restore job itself keeps running server-side; this function tags the
resource if AWS Backup has assigned it a CreatedResourceArn by then (so it
becomes identifiable and IAM-deletable for manual or follow-up cleanup), but
cannot always delete it itself within this invocation. Splitting the
start/poll/cleanup steps across an EventBridge-driven restore-job-completed
flow (rather than one blocking Lambda invocation) would remove this
limitation if RDS restore testing on realistically-sized databases becomes a
requirement; EBS restores complete in well under the budget above today.
"""

import json
import logging
import os
import time
from typing import Any, Optional

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

backup_client = boto3.client("backup")
ec2_client = boto3.client("ec2")
rds_client = boto3.client("rds")

# Resource types this function knows how to restore, validate and tear down.
# Extend _restore_metadata / _tag_restored_resource / _validate_restore /
# _delete_restored_resource together when adding a new type.
SUPPORTED_RESOURCE_TYPES = ("EBS", "RDS")

RESTORE_JOB_POLL_SECONDS = 15
# Leaves headroom under the Lambda's own timeout (900s, main.tf) for the
# tag/validate/delete steps that follow. See the module docstring's "Known
# limitation" note: this is not enough for a realistically-sized RDS restore.
RESTORE_JOB_TIMEOUT_SECONDS = 780


class RestoreJobTimeout(TimeoutError):
    """Raised when a restore job does not reach COMPLETED within budget.

    Carries whatever AWS Backup had already assigned by the time we gave up
    polling, so the caller can still tag (and thereby make cleanable) a
    resource that was in fact created, even though this invocation cannot
    wait for it to finish and delete it itself.
    """

    def __init__(self, restore_job_id: str, created_resource_arn: Optional[str], message: str) -> None:
        super().__init__(message)
        self.restore_job_id = restore_job_id
        self.created_resource_arn = created_resource_arn


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Restore, tag, validate and delete the vault's latest recovery point."""
    vault_name = os.environ["BACKUP_VAULT_NAME"]
    restore_role_arn = os.environ["RESTORE_IAM_ROLE_ARN"]
    tag_key = os.environ.get("TEST_TAG_KEY", "BackupRestoreTest")
    tag_value = os.environ.get("TEST_TAG_VALUE", "true")
    resource_type = event.get("resource_type", os.environ.get("RESOURCE_TYPE", "EBS"))

    if resource_type not in SUPPORTED_RESOURCE_TYPES:
        raise ValueError(
            f"Unsupported resource_type '{resource_type}'; expected one of {SUPPORTED_RESOURCE_TYPES}"
        )

    logger.info("Starting backup restore test: vault=%s resource_type=%s", vault_name, resource_type)

    recovery_point = _latest_recovery_point(vault_name, resource_type)
    if recovery_point is None:
        message = f"No completed recovery points of type {resource_type} in vault {vault_name}; nothing to test."
        logger.warning(message)
        return {"statusCode": 200, "body": json.dumps({"skipped": True, "reason": message})}

    try:
        restore_job_id, created_resource_arn = _restore_and_wait(
            vault_name=vault_name,
            recovery_point_arn=recovery_point["RecoveryPointArn"],
            resource_type=resource_type,
            restore_role_arn=restore_role_arn,
        )
    except RestoreJobTimeout as exc:
        if exc.created_resource_arn:
            logger.warning(
                "Restore job %s timed out but AWS Backup had already created %s; "
                "tagging it now so it stays identifiable and IAM-deletable for cleanup.",
                exc.restore_job_id,
                exc.created_resource_arn,
            )
            _tag_restored_resource(resource_type, exc.created_resource_arn, tag_key, tag_value)
        raise

    # Tag before validating: if validation raises (not just returns an
    # unhealthy result), the finally block below still deletes the resource
    # instead of leaving it orphaned and, being untagged before this point,
    # un-deletable by this role's own IAM policy.
    _tag_restored_resource(resource_type, created_resource_arn, tag_key, tag_value)
    try:
        healthy = _validate_restore(resource_type, created_resource_arn)
    finally:
        _delete_restored_resource(resource_type, created_resource_arn)

    result = {
        "recoveryPointArn": recovery_point["RecoveryPointArn"],
        "restoreJobId": restore_job_id,
        "createdResourceArn": created_resource_arn,
        "healthy": healthy,
    }
    logger.info("Backup restore test complete: %s", json.dumps(result))

    if not healthy:
        raise RuntimeError(f"Restored resource {created_resource_arn} failed validation: {json.dumps(result)}")

    return {"statusCode": 200, "body": json.dumps(result)}


def _latest_recovery_point(vault_name: str, resource_type: str) -> Optional[dict[str, Any]]:
    """Return the most recently completed recovery point of resource_type, or None."""
    paginator = backup_client.get_paginator("list_recovery_points_by_backup_vault")
    candidates = []
    for page in paginator.paginate(BackupVaultName=vault_name, ByResourceType=resource_type):
        candidates.extend(rp for rp in page.get("RecoveryPoints", []) if rp.get("Status") == "COMPLETED")
    if not candidates:
        return None
    return max(candidates, key=lambda rp: rp["CreationDate"])


def _restore_and_wait(
    vault_name: str, recovery_point_arn: str, resource_type: str, restore_role_arn: str
) -> tuple[str, str]:
    """Start a restore job and block, within the Lambda's own timeout, until it finishes.

    restore_role_arn must be a role trusted by backup.amazonaws.com (the
    backup component's own service role, aws_iam_role.backup) -- AWS Backup
    assumes it to perform the actual ec2:CreateVolume /
    rds:RestoreDBInstanceFromDBSnapshot calls, not this function's own role.
    """
    metadata = _restore_metadata(vault_name, recovery_point_arn, resource_type)
    start = backup_client.start_restore_job(
        RecoveryPointArn=recovery_point_arn,
        Metadata=metadata,
        IamRoleArn=restore_role_arn,
        ResourceType=resource_type,
        IdempotencyToken=recovery_point_arn.rsplit(":", 1)[-1],
    )
    restore_job_id = start["RestoreJobId"]

    deadline = time.monotonic() + RESTORE_JOB_TIMEOUT_SECONDS
    while True:
        status = backup_client.describe_restore_job(RestoreJobId=restore_job_id)
        state = status["Status"]
        if state == "COMPLETED":
            return restore_job_id, status["CreatedResourceArn"]
        if state in ("ABORTED", "FAILED"):
            raise RuntimeError(f"Restore job {restore_job_id} ended in {state}: {status.get('StatusMessage')}")
        if time.monotonic() > deadline:
            raise RestoreJobTimeout(
                restore_job_id,
                status.get("CreatedResourceArn"),
                f"Restore job {restore_job_id} did not complete within {RESTORE_JOB_TIMEOUT_SECONDS}s",
            )
        time.sleep(RESTORE_JOB_POLL_SECONDS)


def _restore_metadata(vault_name: str, recovery_point_arn: str, resource_type: str) -> dict[str, str]:
    """Metadata AWS Backup's StartRestoreJob requires for this resource type.

    Seeded from backup:GetRecoveryPointRestoreMetadata -- the source
    resource's own restore metadata (for RDS: subnet group, security groups,
    encryption/KMS key, instance class, etc; for EBS: availabilityZone,
    encrypted, kmsKeyId, volumeType) -- rather than a bare hand-built dict, so
    a restore doesn't silently drop into default networking/encryption
    settings. Only the identifier is overridden.
    """
    base = backup_client.get_recovery_point_restore_metadata(
        BackupVaultName=vault_name, RecoveryPointArn=recovery_point_arn
    )["RestoreMetadata"]
    suffix = str(int(time.time()))
    if resource_type == "EBS":
        # availabilityZone is required and not part of the source volume's
        # own restore metadata (a volume doesn't carry a target AZ), so it is
        # always set explicitly rather than overridden from `base`.
        return {**base, "availabilityZone": _first_availability_zone()}
    if resource_type == "RDS":
        # StartRestoreJob's RDS metadata key is DBInstanceIdentifier (the
        # RestoreDBInstanceFromDBSnapshot parameter name), not
        # TargetDBInstanceIdentifier -- the latter is silently ignored by the
        # API, so the previous version of this function restored into a
        # random, AWS-generated identifier every time. The fixed
        # RDS_RESTORE_TEST_DB_PREFIX below must match
        # local.restore_test_db_prefix in main.tf, which scopes this
        # function's own IAM policy's rds:AddTagsToResource/
        # rds:DeleteDBInstance grants to that exact ARN prefix.
        #
        # DeletionProtection and MultiAZ are overridden alongside the
        # identifier: `base` is seeded from the source instance's own
        # restore metadata, so a prod source with deletion_protection=true
        # (stacks/catalog/rds/prod.yaml) would otherwise carry that setting
        # onto this ephemeral test instance and make
        # _delete_restored_resource fail; Multi-AZ is disabled too, since
        # this instance only exists long enough to validate the restore and
        # is deleted right after.
        prefix = os.environ.get("RDS_RESTORE_TEST_DB_PREFIX", "restore-test-")
        return {
            **base,
            "DBInstanceIdentifier": f"{prefix}{suffix}",
            "DeletionProtection": "false",
            "MultiAZ": "false",
        }
    raise ValueError(f"No restore metadata builder for resource_type '{resource_type}'")


def _first_availability_zone() -> str:
    zones = ec2_client.describe_availability_zones(Filters=[{"Name": "state", "Values": ["available"]}])
    return zones["AvailabilityZones"][0]["ZoneName"]


def _tag_restored_resource(resource_type: str, resource_arn: str, tag_key: str, tag_value: str) -> None:
    """Tag the resource the restore job just created with the test marker tag.

    This is the tag this function's own IAM policy requires (aws:ResourceTag
    condition) before it will delete the resource again, so a restore that
    is not this test's own creation never becomes deletable by this code.
    """
    if resource_type == "EBS":
        volume_id = resource_arn.rsplit("/", 1)[-1]
        ec2_client.create_tags(Resources=[volume_id], Tags=[{"Key": tag_key, "Value": tag_value}])
    elif resource_type == "RDS":
        rds_client.add_tags_to_resource(ResourceName=resource_arn, Tags=[{"Key": tag_key, "Value": tag_value}])
    else:
        raise ValueError(f"No tagging support for resource_type '{resource_type}'")


def _validate_restore(resource_type: str, resource_arn: str) -> bool:
    """Return True once the restored resource reports a healthy state."""
    if resource_type == "EBS":
        volume_id = resource_arn.rsplit("/", 1)[-1]
        volumes = ec2_client.describe_volumes(VolumeIds=[volume_id])["Volumes"]
        return bool(volumes) and volumes[0]["State"] == "available"
    if resource_type == "RDS":
        db_instance_id = resource_arn.rsplit(":", 1)[-1]
        instances = rds_client.describe_db_instances(DBInstanceIdentifier=db_instance_id)["DBInstances"]
        return bool(instances) and instances[0]["DBInstanceStatus"] == "available"
    raise ValueError(f"No validation support for resource_type '{resource_type}'")


def _delete_restored_resource(resource_type: str, resource_arn: str) -> None:
    """Delete the restore-test resource.

    Requires the BackupRestoreTest tag, enforced server-side by the
    aws:ResourceTag condition on this function's own IAM policy -- not just
    by this code path.
    """
    if resource_type == "EBS":
        volume_id = resource_arn.rsplit("/", 1)[-1]
        ec2_client.delete_volume(VolumeId=volume_id)
        logger.info("Deleted restore-test EBS volume %s", volume_id)
    elif resource_type == "RDS":
        db_instance_id = resource_arn.rsplit(":", 1)[-1]
        rds_client.delete_db_instance(DBInstanceIdentifier=db_instance_id, SkipFinalSnapshot=True)
        logger.info("Deleted restore-test RDS instance %s", db_instance_id)
    else:
        raise ValueError(f"No delete support for resource_type '{resource_type}'")
