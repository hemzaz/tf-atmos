"""
Unused Resource Cleanup Lambda Function

Sweeps for unattached EBS volumes, old EBS snapshots and unassociated
Elastic IPs. Only ever touches resources carrying both the account's
Environment tag and the opt-in TAG_KEY/TAG_VALUE (CostOptimization=
cleanup-eligible by default) - this matches the execution role's IAM
Condition (see iam.tf), so a resource must be deliberately opted in before
this function can delete it. Honors DRY_RUN: when true (the default),
candidates are only logged and included in the SNS summary, nothing is
deleted.
"""

import boto3
import json
import os
from datetime import datetime, timedelta, timezone
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
sns = boto3.client('sns')


def handler(event, context):
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    dry_run = os.environ.get('DRY_RUN', 'true').lower() == 'true'
    tag_key = os.environ.get('TAG_KEY', 'CostOptimization')
    tag_value = os.environ.get('TAG_VALUE', 'cleanup-eligible')
    sns_topic = os.environ['SNS_TOPIC']
    retention_days = int(os.environ.get('SNAPSHOT_RETENTION_DAYS', '30'))

    logger.info(
        f"Starting resource cleanup: Environment={environment}, DryRun={dry_run}, "
        f"Tag={tag_key}={tag_value}"
    )

    results = {'dry_run': dry_run, 'volumes': [], 'snapshots': [], 'eips': []}

    try:
        if os.environ.get('CLEANUP_UNUSED_VOLUMES', 'true').lower() == 'true':
            results['volumes'] = cleanup_unused_volumes(tag_key, tag_value, dry_run)

        if os.environ.get('CLEANUP_OLD_SNAPSHOTS', 'true').lower() == 'true':
            results['snapshots'] = cleanup_old_snapshots(tag_key, tag_value, retention_days, dry_run)

        if os.environ.get('CLEANUP_UNUSED_EIPS', 'true').lower() == 'true':
            results['eips'] = cleanup_unused_eips(tag_key, tag_value, dry_run)

        logger.info(f"Cleanup completed: {json.dumps(results, default=str)}")

        publish_summary(sns_topic, environment, results)

        return {'statusCode': 200, 'body': json.dumps(results, default=str)}

    except Exception as e:
        logger.error(f"Cleanup error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}


def cleanup_unused_volumes(tag_key, tag_value, dry_run):
    """
    Delete (or, in dry-run, report) available (unattached) EBS volumes
    carrying the opt-in tag.
    """
    results = []

    response = ec2.describe_volumes(
        Filters=[
            {'Name': 'status', 'Values': ['available']},
            {'Name': f'tag:{tag_key}', 'Values': [tag_value]},
        ]
    )

    for volume in response['Volumes']:
        volume_id = volume['VolumeId']

        if dry_run:
            logger.info(f"[DRY RUN] Would delete unattached volume: {volume_id}")
        else:
            ec2.delete_volume(VolumeId=volume_id)
            logger.info(f"Deleted unattached volume: {volume_id}")

        results.append({
            'id': volume_id,
            'size_gb': volume.get('Size'),
            'action': 'would_delete' if dry_run else 'deleted',
        })

    return results


def cleanup_old_snapshots(tag_key, tag_value, retention_days, dry_run):
    """
    Delete (or, in dry-run, report) self-owned snapshots older than
    retention_days and carrying the opt-in tag, skipping any snapshot still
    backing a registered AMI.
    """
    results = []
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)

    snapshots_in_use = set()
    images = ec2.describe_images(Owners=['self'])
    for image in images['Images']:
        for mapping in image.get('BlockDeviceMappings', []):
            snapshot_id = mapping.get('Ebs', {}).get('SnapshotId')
            if snapshot_id:
                snapshots_in_use.add(snapshot_id)

    response = ec2.describe_snapshots(
        OwnerIds=['self'],
        Filters=[{'Name': f'tag:{tag_key}', 'Values': [tag_value]}],
    )

    for snapshot in response['Snapshots']:
        snapshot_id = snapshot['SnapshotId']

        if snapshot['StartTime'] >= cutoff:
            continue

        if snapshot_id in snapshots_in_use:
            logger.info(f"Skipped snapshot still backing an AMI: {snapshot_id}")
            continue

        if dry_run:
            logger.info(f"[DRY RUN] Would delete old snapshot: {snapshot_id}")
        else:
            ec2.delete_snapshot(SnapshotId=snapshot_id)
            logger.info(f"Deleted old snapshot: {snapshot_id}")

        results.append({
            'id': snapshot_id,
            'start_time': snapshot['StartTime'].isoformat(),
            'action': 'would_delete' if dry_run else 'deleted',
        })

    return results


def cleanup_unused_eips(tag_key, tag_value, dry_run):
    """
    Release (or, in dry-run, report) Elastic IPs that are not associated with
    an instance or network interface and carry the opt-in tag.
    """
    results = []

    response = ec2.describe_addresses(
        Filters=[{'Name': f'tag:{tag_key}', 'Values': [tag_value]}]
    )

    for address in response['Addresses']:
        if address.get('InstanceId') or address.get('NetworkInterfaceId'):
            continue

        allocation_id = address.get('AllocationId')
        if not allocation_id:
            continue

        if dry_run:
            logger.info(f"[DRY RUN] Would release unused EIP: {allocation_id}")
        else:
            ec2.release_address(AllocationId=allocation_id)
            logger.info(f"Released unused EIP: {allocation_id}")

        results.append({
            'allocation_id': allocation_id,
            'public_ip': address.get('PublicIp'),
            'action': 'would_release' if dry_run else 'released',
        })

    return results


def publish_summary(sns_topic, environment, results):
    total = len(results['volumes']) + len(results['snapshots']) + len(results['eips'])
    if total == 0:
        return

    try:
        sns.publish(
            TopicArn=sns_topic,
            Subject=f"[{environment}] Weekly resource cleanup ({'dry run' if results['dry_run'] else 'applied'})",
            Message=json.dumps(results, indent=2, default=str),
        )
        logger.info("Published cleanup summary to SNS")
    except Exception as e:
        logger.error(f"Failed to publish cleanup summary: {str(e)}")
