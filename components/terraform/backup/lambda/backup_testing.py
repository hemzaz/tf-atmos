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
condition on ec2:DeleteVolume/rds:DeleteDBInstance) and can only apply the
tag itself via a request that sets that exact tag (an aws:RequestTag
condition on ec2:CreateTags/rds:AddTagsToResource). A bug in this code can
therefore never delete an arbitrary, untagged volume or database (this was
the M11 finding this function's IAM policy fixes).
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
# tag/validate/delete steps that follow.
RESTORE_JOB_TIMEOUT_SECONDS = 780


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

    restore_job_id, created_resource_arn = _restore_and_wait(
        recovery_point_arn=recovery_point["RecoveryPointArn"],
        resource_type=resource_type,
        restore_role_arn=restore_role_arn,
    )

    _tag_restored_resource(resource_type, created_resource_arn, tag_key, tag_value)
    healthy = _validate_restore(resource_type, created_resource_arn)
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


def _restore_and_wait(recovery_point_arn: str, resource_type: str, restore_role_arn: str) -> tuple[str, str]:
    """Start a restore job and block, within the Lambda's own timeout, until it finishes.

    restore_role_arn must be a role trusted by backup.amazonaws.com (the
    backup component's own service role, aws_iam_role.backup) -- AWS Backup
    assumes it to perform the actual ec2:CreateVolume /
    rds:RestoreDBInstanceFromDBSnapshot calls, not this function's own role.
    """
    metadata = _restore_metadata(resource_type)
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
            raise TimeoutError(f"Restore job {restore_job_id} did not complete within {RESTORE_JOB_TIMEOUT_SECONDS}s")
        time.sleep(RESTORE_JOB_POLL_SECONDS)


def _restore_metadata(resource_type: str) -> dict[str, str]:
    """Metadata AWS Backup's StartRestoreJob requires for this resource type."""
    suffix = str(int(time.time()))
    if resource_type == "EBS":
        return {"availabilityZone": _first_availability_zone()}
    if resource_type == "RDS":
        return {"TargetDBInstanceIdentifier": f"backup-restore-test-{suffix}"}
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
