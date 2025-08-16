#!/usr/bin/env python3
"""
Terraform Lock Cleanup Lambda Function

This function periodically scans the DynamoDB table used for Terraform state locking
and removes locks that have exceeded the maximum age threshold. This serves as a 
safety mechanism to prevent permanently stuck locks from blocking Terraform operations.

Features:
- Configurable maximum lock age
- Detailed logging for audit trails
- Safe operation with dry-run mode
- CloudWatch metrics integration
- Error handling and notification
"""

import json
import logging
import os
import boto3
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main lambda handler function
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing execution summary
    """
    
    # Get configuration from environment variables
    table_name = os.environ.get('TABLE_NAME', 'terraform-state-lock')
    max_lock_age_hours = int(os.environ.get('MAX_LOCK_AGE_HOURS', '24'))
    dry_run = os.environ.get('DRY_RUN', 'true').lower() == 'true'
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    logger.info(f"Starting lock cleanup for table: {table_name}")
    logger.info(f"Max lock age: {max_lock_age_hours} hours")
    logger.info(f"Dry run mode: {dry_run}")
    
    try:
        # Get the DynamoDB table
        table = dynamodb.Table(table_name)
        
        # Calculate cutoff time
        cutoff_time = datetime.utcnow() - timedelta(hours=max_lock_age_hours)
        cutoff_timestamp = int(cutoff_time.timestamp())
        
        logger.info(f"Cutoff timestamp: {cutoff_timestamp} ({cutoff_time.isoformat()})")
        
        # Scan for stale locks
        stale_locks = scan_for_stale_locks(table, cutoff_timestamp)
        
        logger.info(f"Found {len(stale_locks)} stale locks")
        
        # Process stale locks
        cleanup_summary = process_stale_locks(table, stale_locks, dry_run)
        
        # Send CloudWatch metrics
        send_metrics(table_name, cleanup_summary)
        
        # Send notification if locks were cleaned up
        if cleanup_summary['deleted_count'] > 0 and sns_topic_arn:
            send_notification(sns_topic_arn, cleanup_summary, table_name, dry_run)
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'table_name': table_name,
                'cutoff_time': cutoff_time.isoformat(),
                'dry_run': dry_run,
                'summary': cleanup_summary
            }, indent=2)
        }
        
        logger.info(f"Lock cleanup completed successfully: {cleanup_summary}")
        return response
        
    except Exception as e:
        logger.error(f"Lock cleanup failed: {str(e)}", exc_info=True)
        
        # Send error notification
        if sns_topic_arn:
            send_error_notification(sns_topic_arn, str(e), table_name)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'table_name': table_name
            })
        }

def scan_for_stale_locks(table, cutoff_timestamp: int) -> List[Dict[str, Any]]:
    """
    Scan DynamoDB table for stale locks
    
    Args:
        table: DynamoDB table resource
        cutoff_timestamp: Unix timestamp cutoff for stale locks
        
    Returns:
        List of stale lock items
    """
    
    stale_locks = []
    
    try:
        # Scan the entire table to find stale locks
        paginator = table.meta.client.get_paginator('scan')
        page_iterator = paginator.paginate(TableName=table.name)
        
        for page in page_iterator:
            for item in page.get('Items', []):
                lock_id = item.get('LockID', {}).get('S', '')
                
                # Parse timestamp from lock info if available
                info = item.get('Info', {}).get('S', '{}')
                
                try:
                    lock_info = json.loads(info)
                    created_time = lock_info.get('Created', '')
                    
                    if created_time:
                        # Parse ISO timestamp to Unix timestamp
                        created_dt = datetime.fromisoformat(created_time.replace('Z', '+00:00'))
                        created_timestamp = int(created_dt.timestamp())
                        
                        if created_timestamp < cutoff_timestamp:
                            stale_locks.append({
                                'LockID': lock_id,
                                'Created': created_time,
                                'CreatedTimestamp': created_timestamp,
                                'Info': lock_info,
                                'Item': item
                            })
                            
                            logger.info(f"Found stale lock: {lock_id} (created: {created_time})")
                    else:
                        logger.warning(f"Lock {lock_id} has no creation timestamp")
                        
                except (json.JSONDecodeError, ValueError) as e:
                    logger.warning(f"Could not parse lock info for {lock_id}: {e}")
                    continue
                    
    except Exception as e:
        logger.error(f"Error scanning for stale locks: {e}")
        raise
    
    return stale_locks

def process_stale_locks(table, stale_locks: List[Dict[str, Any]], dry_run: bool) -> Dict[str, Any]:
    """
    Process and optionally delete stale locks
    
    Args:
        table: DynamoDB table resource
        stale_locks: List of stale lock items
        dry_run: Whether to actually delete locks or just log them
        
    Returns:
        Summary of processing results
    """
    
    summary = {
        'total_found': len(stale_locks),
        'deleted_count': 0,
        'failed_count': 0,
        'deleted_locks': [],
        'failed_locks': []
    }
    
    for lock in stale_locks:
        lock_id = lock['LockID']
        
        try:
            if not dry_run:
                # Delete the lock
                table.delete_item(
                    Key={'LockID': lock_id},
                    ConditionExpression='LockID = :lock_id',
                    ExpressionAttributeValues={':lock_id': lock_id}
                )
                
                logger.info(f"Deleted stale lock: {lock_id}")
                summary['deleted_count'] += 1
                summary['deleted_locks'].append({
                    'lock_id': lock_id,
                    'created': lock['Created'],
                    'operation': lock['Info'].get('Operation', 'unknown'),
                    'path': lock['Info'].get('Path', 'unknown')
                })
            else:
                logger.info(f"[DRY RUN] Would delete stale lock: {lock_id}")
                summary['deleted_count'] += 1
                summary['deleted_locks'].append({
                    'lock_id': lock_id,
                    'created': lock['Created'],
                    'operation': lock['Info'].get('Operation', 'unknown'),
                    'path': lock['Info'].get('Path', 'unknown')
                })
                
        except Exception as e:
            logger.error(f"Failed to delete lock {lock_id}: {e}")
            summary['failed_count'] += 1
            summary['failed_locks'].append({
                'lock_id': lock_id,
                'error': str(e)
            })
    
    return summary

def send_metrics(table_name: str, summary: Dict[str, Any]) -> None:
    """
    Send metrics to CloudWatch
    
    Args:
        table_name: Name of the DynamoDB table
        summary: Cleanup summary data
    """
    
    try:
        cloudwatch.put_metric_data(
            Namespace='TerraformLockCleanup',
            MetricData=[
                {
                    'MetricName': 'StaleLocks',
                    'Value': summary['total_found'],
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'TableName',
                            'Value': table_name
                        }
                    ]
                },
                {
                    'MetricName': 'DeletedLocks',
                    'Value': summary['deleted_count'],
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'TableName',
                            'Value': table_name
                        }
                    ]
                },
                {
                    'MetricName': 'FailedDeletions',
                    'Value': summary['failed_count'],
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'TableName',
                            'Value': table_name
                        }
                    ]
                }
            ]
        )
        
        logger.info("CloudWatch metrics sent successfully")
        
    except Exception as e:
        logger.warning(f"Failed to send CloudWatch metrics: {e}")

def send_notification(sns_topic_arn: str, summary: Dict[str, Any], table_name: str, dry_run: bool) -> None:
    """
    Send notification about cleanup results
    
    Args:
        sns_topic_arn: SNS topic ARN for notifications
        summary: Cleanup summary data
        table_name: Name of the DynamoDB table
        dry_run: Whether this was a dry run
    """
    
    try:
        mode = "DRY RUN" if dry_run else "LIVE"
        subject = f"Terraform Lock Cleanup Report - {table_name} ({mode})"
        
        message = f"""
Terraform Lock Cleanup Report

Table: {table_name}
Mode: {mode}
Timestamp: {datetime.utcnow().isoformat()}

Summary:
- Stale locks found: {summary['total_found']}
- Locks deleted: {summary['deleted_count']}
- Failed deletions: {summary['failed_count']}

Deleted Locks:
"""
        
        for lock in summary['deleted_locks'][:10]:  # Limit to first 10 for brevity
            message += f"- {lock['lock_id']} (created: {lock['created']}, operation: {lock['operation']})\n"
        
        if len(summary['deleted_locks']) > 10:
            message += f"... and {len(summary['deleted_locks']) - 10} more\n"
        
        if summary['failed_locks']:
            message += "\nFailed Deletions:\n"
            for lock in summary['failed_locks']:
                message += f"- {lock['lock_id']}: {lock['error']}\n"
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        
        logger.info("Notification sent successfully")
        
    except Exception as e:
        logger.warning(f"Failed to send notification: {e}")

def send_error_notification(sns_topic_arn: str, error: str, table_name: str) -> None:
    """
    Send error notification
    
    Args:
        sns_topic_arn: SNS topic ARN for notifications
        error: Error message
        table_name: Name of the DynamoDB table
    """
    
    try:
        subject = f"Terraform Lock Cleanup ERROR - {table_name}"
        
        message = f"""
Terraform Lock Cleanup Error

Table: {table_name}
Timestamp: {datetime.utcnow().isoformat()}

Error:
{error}

Please check CloudWatch logs for more details.
        """
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        
        logger.info("Error notification sent successfully")
        
    except Exception as e:
        logger.warning(f"Failed to send error notification: {e}")