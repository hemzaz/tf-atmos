"""
S3 Event Processor Lambda Function
"""

import json
import logging
import os
import urllib.parse
import boto3

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Initialize S3 client
s3 = boto3.client('s3')

def handler(event, context):
    """
    Lambda function handler for processing S3 events
    
    Parameters:
    - event: The event data from S3 trigger
    - context: Lambda context object
    
    Returns:
    - dict: Processing result
    """
    logger.info("Received S3 event: %s", json.dumps(event))
    
    # Process each S3 event record
    for record in event.get('Records', []):
        # Extract bucket and key information
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        logger.info("Processing file: s3://%s/%s", bucket, key)
        
        try:
            # Get the object from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')
            
            # Parse JSON content
            data = json.loads(content)
            logger.info("File content: %s", json.dumps(data))
            
            # Process the data (example: count items)
            item_count = len(data) if isinstance(data, list) else 1
            logger.info("Processed %d items from the file", item_count)
            
            # Example: you could transform the data and put it back to S3
            # processed_data = transform_data(data)
            # s3.put_object(
            #     Bucket=bucket,
            #     Key=key.replace('uploads/', 'processed/'),
            #     Body=json.dumps(processed_data)
            # )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f"Successfully processed s3://{bucket}/{key}",
                    'itemCount': item_count
                })
            }
            
        except Exception as e:
            logger.error("Error processing %s/%s: %s", bucket, key, str(e))
            raise e

def transform_data(data):
    """
    Example function to transform data
    This is a placeholder - implement your specific transformation logic
    
    Parameters:
    - data: The data to transform
    
    Returns:
    - The transformed data
    """
    # Add your transformation logic here
    # For example, uppercase all string values if it's a dict
    if isinstance(data, dict):
        return {k: v.upper() if isinstance(v, str) else v for k, v in data.items()}
    return data