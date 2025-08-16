# Lambda Function Examples

This directory contains examples for deploying and configuring AWS Lambda functions using the Atmos framework.

## Basic Lambda Function

Below is an example of how to deploy a simple Lambda function:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    lambda/simple-function:
      vars:
        enabled: true
        region: us-west-2
        
        # Function Definition
        function_name: "simple-processor"
        description: "A simple Lambda function to process events"
        handler: "index.handler"
        runtime: "nodejs18.x"
        timeout: 30
        memory_size: 128
        
        # Source Code
        source_path: "./functions/simple-processor"  # Path relative to the project root
        
        # Environment Variables
        environment_variables: {
          LOG_LEVEL: "INFO",
          REGION: "us-west-2"
        }
        
        # VPC Configuration
        vpc_enabled: false
        
        # Trigger Configuration
        event_source_mappings_enabled: false
        
        # Tags
        tags: {
          Environment: "dev",
          Project: "demo"
        }
```

## Lambda Function with API Gateway Integration

For a serverless API endpoint:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    lambda/api-function:
      vars:
        enabled: true
        region: us-west-2
        
        # Function Definition
        function_name: "api-handler"
        description: "Lambda function for API Gateway integration"
        handler: "app.handler"
        runtime: "python3.9"
        timeout: 30
        memory_size: 256
        
        # Source Code
        source_path: "./functions/api-handler"
        
        # Environment Variables
        environment_variables: {
          LOG_LEVEL: "INFO",
          DB_CONNECTION_STRING: "${ssm:/api/db-connection}",
          API_KEY: "${ssm:/api/key}"
        }
        
        # API Gateway Trigger
        allowed_triggers: {
          APIGatewayAny: {
            service: "apigateway"
            source_arn: "${dep.apigateway.outputs.execution_arn}/*/*"
          }
        }
        
        # IAM Permissions
        attach_policies: true
        policies_count: 2
        policies: [
          "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
          "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
        ]
        
        # VPC Configuration
        vpc_enabled: false
        
        # Tags
        tags: {
          Environment: "dev",
          Project: "api-service"
        }
```

## Lambda Function with Event Source Mapping

For processing events from a queue:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    lambda/event-processor:
      vars:
        enabled: true
        region: us-west-2
        
        # Function Definition
        function_name: "queue-processor"
        description: "Process messages from SQS queue"
        handler: "processor.handler"
        runtime: "nodejs18.x"
        timeout: 60
        memory_size: 512
        
        # Source Code
        source_path: "./functions/queue-processor"
        
        # Environment Variables
        environment_variables: {
          LOG_LEVEL: "INFO",
          DLQ_URL: "${dep.sqs.outputs.dlq_url}"
        }
        
        # Event Source Mapping
        event_source_mappings_enabled: true
        event_source_mappings: [
          {
            event_source_arn: "${dep.sqs.outputs.queue_arn}"
            batch_size: 10
            maximum_batching_window_in_seconds: 30
            enabled: true
          }
        ]
        
        # IAM Permissions
        attach_policies: true
        policies_count: 2
        policies: [
          "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
          "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
        ]
        
        # VPC Configuration
        vpc_enabled: false
        
        # Tags
        tags: {
          Environment: "production",
          Project: "event-processor"
        }
```

## Lambda Function in VPC with Enhanced Monitoring

For production-ready Lambda with VPC access and monitoring:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    lambda/vpc-function:
      vars:
        enabled: true
        region: us-west-2
        
        # Function Definition
        function_name: "database-processor"
        description: "Access RDS within VPC"
        handler: "app.handler"
        runtime: "python3.9"
        timeout: 120
        memory_size: 1024
        
        # Source Code
        source_path: "./functions/database-processor"
        layers: [
          "arn:aws:lambda:us-west-2:123456789012:layer:SQLAlchemyLayer:1"
        ]
        
        # Environment Variables
        environment_variables: {
          LOG_LEVEL: "INFO",
          DB_CONNECTION: "${ssm:/prod/db/connection}",
          SECRETS_ARN: "arn:aws:secretsmanager:us-west-2:123456789012:secret:db-creds"
        }
        
        # VPC Configuration
        vpc_enabled: true
        vpc_subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        vpc_security_group_ids: [
          ${dep.securitygroup.outputs.lambda_sg_id}
        ]
        
        # Monitoring
        enable_cloudwatch_logs: true
        cloudwatch_logs_retention_in_days: 30
        tracing_config_mode: "Active"  # AWS X-Ray tracing
        
        # IAM Permissions
        attach_policies: true
        policies_count: 3
        policies: [
          "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
          "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
          "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
        ]
        
        # Tags
        tags: {
          Environment: "production",
          Project: "database-service"
        }
```

## Implementation Notes

1. **Security Best Practices**:
   - Store sensitive configuration in SSM Parameter Store or Secrets Manager
   - Use the principle of least privilege when assigning IAM permissions
   - For VPC-connected functions, use security groups to restrict access
   - Consider KMS encryption for environment variables containing sensitive data

2. **Performance Optimization**:
   - Allocate appropriate memory based on function requirements
   - Use Lambda Layers for common dependencies
   - Set timeouts based on expected function duration
   - Consider provisioned concurrency for latency-sensitive functions

3. **Cost Optimization**:
   - Optimize memory allocation to reduce costs
   - Set appropriate timeout values
   - Use event filtering to reduce unnecessary invocations
   - Consider using AWS Graviton processors for better price-performance

4. **Operational Excellence**:
   - Enable X-Ray tracing for production functions
   - Set appropriate CloudWatch logs retention periods
   - Implement structured logging within functions
   - Consider using Lambda Insights for enhanced monitoring