"""
State management for Terraform operations.
Handles Terraform state locks and provides tools for detecting and cleaning abandoned locks.
"""

import os
import re
import json
import time
import datetime
from typing import Dict, List, Optional, Any, Tuple
from pathlib import Path
import subprocess

import boto3
from botocore.exceptions import ClientError
from dateutil import parser

from gaia.logger import get_logger
from gaia.utils import run_command

logger = get_logger(__name__)


def get_state_config(stack: str) -> Dict[str, str]:
    """
    Get Terraform state configuration for a stack.
    
    Args:
        stack: Stack name
        
    Returns:
        Dictionary with bucket, table, region, and state_key_pattern
    """
    # Parse stack parts
    stack_parts = stack.split('-')
    if len(stack_parts) < 3:
        raise ValueError(f"Invalid stack name: {stack}. Expected format: tenant-account-environment")
    
    tenant = stack_parts[0]
    account = stack_parts[1]
    
    try:
        # Get backend config from atmos
        cmd = ["atmos", "terraform", "backend-config", "-s", stack]
        result = run_command(cmd)
        
        # Extract backend config values
        config_text = result.stdout
        
        # Parse backend config with regex
        bucket_match = re.search(r'bucket\s*=\s*"?([^"]*)"?', config_text)
        table_match = re.search(r'dynamodb_table\s*=\s*"?([^"]*)"?', config_text)
        region_match = re.search(r'region\s*=\s*"?([^"]*)"?', config_text)
        key_match = re.search(r'key\s*=\s*"?([^"]*)"?', config_text)
        
        # Extract values or use defaults
        bucket = bucket_match.group(1) if bucket_match else f"{tenant}-{account}-terraform-state"
        table = table_match.group(1) if table_match else f"{tenant}-{account}-terraform-locks"
        region = region_match.group(1) if region_match else "us-east-1"
        state_key_pattern = key_match.group(1) if key_match else "terraform/%stack%/%component%/terraform.tfstate"
        
        return {
            "bucket": bucket,
            "table": table,
            "region": region,
            "state_key_pattern": state_key_pattern
        }
    except Exception as e:
        logger.error(f"Failed to get state config for stack {stack}: {e}")
        
        # Use default naming convention as fallback
        return {
            "bucket": f"{tenant}-{account}-terraform-state",
            "table": f"{tenant}-{account}-terraform-locks",
            "region": "us-east-1",
            "state_key_pattern": "terraform/%stack%/%component%/terraform.tfstate"
        }


def parse_iso8601_timestamp(timestamp: str) -> float:
    """
    Parse ISO8601 timestamp to Unix timestamp.
    Handles various ISO8601 formats including those with fractional seconds.
    
    Args:
        timestamp: ISO8601 timestamp
        
    Returns:
        Unix timestamp (seconds since epoch)
    """
    try:
        # Use dateutil parser which handles most ISO8601 formats
        dt = parser.parse(timestamp)
        
        # Convert to UTC timestamp
        return dt.timestamp()
    except Exception as e:
        logger.error(f"Failed to parse timestamp {timestamp}: {e}")
        return 0


def list_state_locks(stack: str) -> List[Dict[str, Any]]:
    """
    List current Terraform state locks.
    
    Args:
        stack: Stack name
        
    Returns:
        List of lock information dictionaries
    """
    # Get state config
    state_config = get_state_config(stack)
    bucket = state_config["bucket"]
    table = state_config["table"]
    region = state_config["region"]
    
    logger.info(f"Checking for state locks in DynamoDB table {table}...")
    
    try:
        # Create DynamoDB client
        dynamodb = boto3.client('dynamodb', region_name=region)
        
        # Scan DynamoDB table for locks
        response = dynamodb.scan(
            TableName=table,
            AttributesToGet=["LockID", "Info", "Created"]
        )
        
        locks = []
        for item in response.get('Items', []):
            lock_id = item.get('LockID', {}).get('S', '')
            created = item.get('Created', {}).get('S', '')
            info = item.get('Info', {}).get('S', '')
            
            try:
                # Parse info JSON
                info_json = json.loads(info) if info else {}
            except json.JSONDecodeError:
                info_json = {"raw": info}
            
            locks.append({
                "lock_id": lock_id,
                "created": created,
                "created_timestamp": parse_iso8601_timestamp(created),
                "info": info_json
            })
        
        if not locks:
            logger.info("No active state locks found.")
        else:
            logger.warning(f"Found {len(locks)} active state locks:")
            for lock in locks:
                logger.info(f"ID: {lock['lock_id']}")
                logger.info(f"Created: {lock['created']}")
                logger.info(f"Info: {json.dumps(lock['info'], indent=2)}")
                logger.info("---")
        
        return locks
    
    except ClientError as e:
        logger.error(f"AWS API error: {e}")
        return []
    except Exception as e:
        logger.error(f"Error listing state locks: {e}")
        return []


def detect_abandoned_locks(stack: str, older_than: int = 120) -> List[Dict[str, Any]]:
    """
    Detect abandoned Terraform state locks.
    
    Args:
        stack: Stack name
        older_than: Minutes to consider a lock abandoned
        
    Returns:
        List of abandoned lock information dictionaries
    """
    # Get state config
    state_config = get_state_config(stack)
    bucket = state_config["bucket"]
    table = state_config["table"]
    region = state_config["region"]
    
    logger.info(f"Checking for abandoned state locks (older than {older_than} minutes)...")
    
    try:
        # Get current time in seconds since epoch
        now = time.time()
        cutoff_time = now - older_than * 60
        
        # Get all locks
        locks = list_state_locks(stack)
        
        # Filter for abandoned locks
        abandoned_locks = []
        for lock in locks:
            lock_time = lock["created_timestamp"]
            
            if lock_time > 0 and lock_time < cutoff_time:
                abandoned_locks.append(lock)
        
        if not abandoned_locks:
            logger.info("No abandoned state locks found.")
        else:
            logger.warning(f"Found {len(abandoned_locks)} potentially abandoned state locks:")
            for lock in abandoned_locks:
                logger.info(f"ID: {lock['lock_id']}")
                logger.info(f"Created: {lock['created']}")
                logger.info(f"Info: {json.dumps(lock['info'], indent=2)}")
                logger.info("---")
            
            # Provide guidance for cleanup
            logger.warning("To force unlock a state lock, use:")
            logger.warning("  terraform force-unlock <LOCK_ID>")
            logger.warning("  OR")
            logger.warning(f"  aws dynamodb delete-item --table-name {table} --key '{{\"LockID\":{{\"S\":\"<LOCK_ID>\"}}}}' --region {region}")
        
        return abandoned_locks
    
    except Exception as e:
        logger.error(f"Error detecting abandoned locks: {e}")
        return []


def clean_abandoned_locks(stack: str, older_than: int = 120, force: bool = False) -> int:
    """
    Clean abandoned Terraform state locks.
    
    Args:
        stack: Stack name
        older_than: Minutes to consider a lock abandoned
        force: Whether to force cleanup in non-interactive mode
        
    Returns:
        Number of locks cleaned
    """
    # Get state config
    state_config = get_state_config(stack)
    bucket = state_config["bucket"]
    table = state_config["table"]
    region = state_config["region"]
    
    logger.warning("Cleaning abandoned state locks is a dangerous operation!")
    logger.warning(f"This will force-remove locks that are older than {older_than} minutes.")
    
    # Confirm operation in interactive mode
    if not force and os.isatty(0):
        response = input("Are you absolutely sure you want to continue? (y/n): ").strip().lower()
        if response != 'y':
            logger.info("Operation cancelled.")
            return 0
    elif not force:
        logger.error("Cannot clean locks in non-interactive mode without force=true.")
        return 0
    
    try:
        # Get abandoned locks
        abandoned_locks = detect_abandoned_locks(stack, older_than)
        
        if not abandoned_locks:
            logger.info("No abandoned locks were found to clean.")
            return 0
        
        # Create DynamoDB client
        dynamodb = boto3.client('dynamodb', region_name=region)
        
        # Clean locks
        cleaned_locks = 0
        for lock in abandoned_locks:
            lock_id = lock["lock_id"]
            created = lock["created"]
            
            logger.warning(f"Removing abandoned lock: {lock_id} (created: {created})")
            
            try:
                # Delete the item from DynamoDB
                dynamodb.delete_item(
                    TableName=table,
                    Key={"LockID": {"S": lock_id}}
                )
                
                logger.info(f"Successfully removed lock: {lock_id}")
                cleaned_locks += 1
            except Exception as e:
                logger.error(f"Failed to remove lock {lock_id}: {e}")
        
        if cleaned_locks > 0:
            logger.info(f"Cleaned {cleaned_locks} abandoned locks.")
        else:
            logger.info("No locks were cleaned.")
        
        return cleaned_locks
    
    except Exception as e:
        logger.error(f"Error cleaning abandoned locks: {e}")
        return 0


def check_state_locks_before_operation(stack: str, operation: str, component: str) -> None:
    """
    Check for state locks before a Terraform operation.
    
    Args:
        stack: Stack name
        operation: Operation being performed
        component: Component being operated on
    """
    # Skip for operations that don't require state lock
    if operation in ["output", "state", "providers", "version", "help"]:
        return
    
    # Check for abandoned locks older than 1 hour
    abandoned_locks = detect_abandoned_locks(stack, 60)
    
    # If destructive operation, warn about potential lock issues
    if operation in ["apply", "destroy", "import"]:
        logger.warning(f"Starting a {operation} operation which will acquire a state lock.")
        logger.warning("If the operation is interrupted, the lock may need to be manually released.")
        logger.warning(f"To check for locks: python -m atmos_cli.tools.list_locks {stack}")
        logger.warning("Run 'terraform force-unlock <ID>' if necessary to release the lock.")
    
    return