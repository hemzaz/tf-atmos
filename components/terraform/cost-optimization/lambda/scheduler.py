"""
Instance Scheduler Lambda Function
Automatically starts and stops EC2 instances and RDS databases based on schedules
"""

import boto3
import json
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2 = boto3.client('ec2')
rds = boto3.client('rds')
autoscaling = boto3.client('autoscaling')

def handler(event, context):
    """
    Main handler for instance scheduling
    """
    environment = os.environ.get('ENVIRONMENT', 'dev')
    action = event.get('action', 'CHECK')
    tag_filters = json.loads(os.environ.get('TAG_FILTERS', '{}'))
    
    logger.info(f"Starting scheduler: Environment={environment}, Action={action}")
    
    results = {
        'ec2_instances': [],
        'rds_instances': [],
        'autoscaling_groups': []
    }
    
    try:
        # Process EC2 instances
        results['ec2_instances'] = process_ec2_instances(action, tag_filters)
        
        # Process RDS instances
        results['rds_instances'] = process_rds_instances(action, tag_filters)
        
        # Process Auto Scaling Groups
        results['autoscaling_groups'] = process_autoscaling_groups(action, tag_filters)
        
        # Log summary
        logger.info(f"Scheduler completed: {json.dumps(results)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results)
        }
        
    except Exception as e:
        logger.error(f"Scheduler error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_ec2_instances(action, tag_filters):
    """
    Start or stop EC2 instances based on action
    """
    results = []
    
    # Build filter for instances
    filters = [
        {'Name': f'tag:{k}', 'Values': [v]} for k, v in tag_filters.items()
    ]
    filters.append({'Name': 'instance-state-name', 'Values': ['running', 'stopped']})
    
    # Get instances
    response = ec2.describe_instances(Filters=filters)
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            current_state = instance['State']['Name']
            
            # Get instance name tag
            name_tag = next((tag['Value'] for tag in instance.get('Tags', []) 
                           if tag['Key'] == 'Name'), instance_id)
            
            if action == 'START' and current_state == 'stopped':
                ec2.start_instances(InstanceIds=[instance_id])
                logger.info(f"Started EC2 instance: {name_tag} ({instance_id})")
                results.append({
                    'id': instance_id,
                    'name': name_tag,
                    'action': 'started',
                    'previous_state': current_state
                })
                
            elif action == 'STOP' and current_state == 'running':
                # Check for do-not-stop tag
                if not has_tag(instance.get('Tags', []), 'DoNotStop', 'true'):
                    ec2.stop_instances(InstanceIds=[instance_id])
                    logger.info(f"Stopped EC2 instance: {name_tag} ({instance_id})")
                    results.append({
                        'id': instance_id,
                        'name': name_tag,
                        'action': 'stopped',
                        'previous_state': current_state
                    })
                else:
                    logger.info(f"Skipped EC2 instance with DoNotStop tag: {name_tag}")
    
    return results

def process_rds_instances(action, tag_filters):
    """
    Start or stop RDS instances based on action
    """
    results = []
    
    # Get all RDS instances
    response = rds.describe_db_instances()
    
    for db_instance in response['DBInstances']:
        db_id = db_instance['DBInstanceIdentifier']
        current_status = db_instance['DBInstanceStatus']
        
        # Get tags for the instance
        tags_response = rds.list_tags_for_resource(
            ResourceName=db_instance['DBInstanceArn']
        )
        tags = {tag['Key']: tag['Value'] for tag in tags_response['TagList']}
        
        # Check if instance matches tag filters
        if not all(tags.get(k) == v for k, v in tag_filters.items()):
            continue
        
        # Check for MultiAZ (don't stop MultiAZ instances)
        if db_instance.get('MultiAZ', False):
            logger.info(f"Skipped MultiAZ RDS instance: {db_id}")
            continue
        
        if action == 'START' and current_status == 'stopped':
            rds.start_db_instance(DBInstanceIdentifier=db_id)
            logger.info(f"Started RDS instance: {db_id}")
            results.append({
                'id': db_id,
                'action': 'started',
                'previous_status': current_status
            })
            
        elif action == 'STOP' and current_status == 'available':
            # Check for do-not-stop tag
            if tags.get('DoNotStop') != 'true':
                rds.stop_db_instance(DBInstanceIdentifier=db_id)
                logger.info(f"Stopped RDS instance: {db_id}")
                results.append({
                    'id': db_id,
                    'action': 'stopped',
                    'previous_status': current_status
                })
            else:
                logger.info(f"Skipped RDS instance with DoNotStop tag: {db_id}")
    
    return results

def process_autoscaling_groups(action, tag_filters):
    """
    Scale Auto Scaling Groups up or down based on action
    """
    results = []
    
    # Get all Auto Scaling Groups
    response = autoscaling.describe_auto_scaling_groups()
    
    for asg in response['AutoScalingGroups']:
        asg_name = asg['AutoScalingGroupName']
        
        # Check tags
        tags = {tag['Key']: tag['Value'] for tag in asg.get('Tags', [])}
        
        # Check if ASG matches tag filters
        if not all(tags.get(k) == v for k, v in tag_filters.items()):
            continue
        
        current_desired = asg['DesiredCapacity']
        current_min = asg['MinSize']
        current_max = asg['MaxSize']
        
        if action == 'START':
            # Restore to tagged capacity or default
            desired = int(tags.get('NormalCapacity', '2'))
            min_size = int(tags.get('NormalMinSize', '1'))
            
            if current_desired == 0:
                autoscaling.update_auto_scaling_group(
                    AutoScalingGroupName=asg_name,
                    MinSize=min_size,
                    DesiredCapacity=desired
                )
                logger.info(f"Scaled up ASG: {asg_name} to {desired} instances")
                results.append({
                    'name': asg_name,
                    'action': 'scaled_up',
                    'previous_capacity': current_desired,
                    'new_capacity': desired
                })
                
        elif action == 'STOP':
            # Scale down to 0 if not critical
            if tags.get('Critical') != 'true':
                # Save current capacity in tags for restoration
                autoscaling.create_or_update_tags(Tags=[
                    {
                        'ResourceId': asg_name,
                        'ResourceType': 'auto-scaling-group',
                        'Key': 'NormalCapacity',
                        'Value': str(current_desired),
                        'PropagateAtLaunch': False
                    },
                    {
                        'ResourceId': asg_name,
                        'ResourceType': 'auto-scaling-group',
                        'Key': 'NormalMinSize',
                        'Value': str(current_min),
                        'PropagateAtLaunch': False
                    }
                ])
                
                # Scale down to 0
                autoscaling.update_auto_scaling_group(
                    AutoScalingGroupName=asg_name,
                    MinSize=0,
                    DesiredCapacity=0
                )
                logger.info(f"Scaled down ASG: {asg_name} to 0 instances")
                results.append({
                    'name': asg_name,
                    'action': 'scaled_down',
                    'previous_capacity': current_desired,
                    'new_capacity': 0
                })
            else:
                logger.info(f"Skipped critical ASG: {asg_name}")
    
    return results

def has_tag(tags, key, value):
    """
    Check if a specific tag exists with the given value
    """
    for tag in tags:
        if tag.get('Key') == key and tag.get('Value') == value:
            return True
    return False