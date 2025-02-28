# Lambda Component

_Last Updated: February 28, 2025_

## Overview

The Lambda component provides a secure, flexible, and comprehensive way to deploy and manage AWS Lambda functions and related resources. It supports various deployment scenarios including API integrations, event-driven architectures, and VPC connectivity, with granular control over permissions, monitoring, and error handling.

Key features include:

- Complete Lambda function lifecycle management
- Multiple trigger/event source integrations (API Gateway, S3, CloudWatch Events, SNS)
- IAM role and policy management with least privilege defaults
- VPC integration with auto-created security groups
- CloudWatch log configuration with retention and encryption
- Event invocation configuration with retry and destination support
- Lambda alias management for deployment strategies
- Dead letter queue configuration
- X-Ray tracing integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Lambda Component                           │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Lambda Function                           │
│                                                             │
│  ┌───────────┐     ┌─────────────┐    ┌─────────────────┐   │
│  │  Source   │     │  Execution  │    │  Configuration  │   │
│  │  Code     │     │  Context    │    │  Settings       │   │
│  └─────┬─────┘     └──────┬──────┘    └────────┬────────┘   │
│        │                  │                    │            │
│        ▼                  ▼                    ▼            │
└─────────────────────────────────────────────────────────────┘
               │                  │                    │
               │                  │                    │
               ▼                  ▼                    ▼
┌─────────────────┐   ┌────────────────┐   ┌─────────────────────┐
│  IAM            │   │  Invocation    │   │  Monitoring         │
│  Permissions    │   │  Sources       │   │  and Logging        │
│                 │   │                │   │                     │
│  ┌───────────┐  │   │  ┌───────────┐ │   │  ┌───────────────┐  │
│  │ Execution │  │   │  │ API       │ │   │  │ CloudWatch    │  │
│  │ Role      │  │   │  │ Gateway   │ │   │  │ Logs          │  │
│  └───────────┘  │   │  └───────────┘ │   │  └───────────────┘  │
│                 │   │                │   │                     │
│  ┌───────────┐  │   │  ┌───────────┐ │   │  ┌───────────────┐  │
│  │ Custom    │  │   │  │ Event     │ │   │  │ X-Ray         │  │
│  │ Policies  │  │   │  │ Sources   │ │   │  │ Tracing       │  │
│  └───────────┘  │   │  └───────────┘ │   │  └───────────────┘  │
└─────────────────┘   └────────────────┘   └─────────────────────┘
         │                    │                      │
         │                    │                      │
         ▼                    ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   Network Integration                        │
│                                                             │
│  ┌───────────────┐    ┌────────────────┐                    │
│  │ VPC           │    │ Security       │                    │
│  │ Access        │    │ Groups         │                    │
│  └───────────────┘    └────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

The Lambda component architecture includes:

1. **Lambda Function**: Core resource with source code, execution context and settings
2. **IAM Permissions**: Role and policies for secure execution
3. **Invocation Sources**: Supported trigger mechanisms (API Gateway, S3, CloudWatch Events, SNS)
4. **Monitoring and Logging**: CloudWatch logs and X-Ray tracing integration
5. **Network Integration**: VPC connectivity with auto-created security groups

The component separates concerns to ensure proper security, monitoring, and integration capabilities while maintaining clean deployment practices.

## Usage

### Basic Lambda Function

```yaml
lambda:
  vars:
    region: "us-west-2"
    function_name: "api-processor"
    handler: "index.handler"
    runtime: "nodejs16.x"
    filename: "/tmp/lambda-code.zip"
    memory_size: 256
    timeout: 30
    
    environment_variables:
      NODE_ENV: "production"
      LOG_LEVEL: "info"
      
    tags:
      Environment: "dev"
      Service: "api"
      Owner: "platform-team"
```

### Lambda with S3 Source and API Gateway Trigger

```yaml
lambda:
  vars:
    region: "us-west-2"
    function_name: "api-handler"
    handler: "app.handler"
    runtime: "nodejs16.x"
    
    # S3 source code
    s3_bucket: "lambda-deployments"
    s3_key: "functions/api-handler.zip"
    source_code_hash: "${base64sha256(file('/tmp/lambda-code.zip'))}"
    
    # API Gateway trigger
    api_gateway_source_arn: "${output.apigateway.execution_arn}/*/GET/*"
    
    # Environmental configuration
    memory_size: 512
    timeout: 30
    log_retention_days: 14
    
    environment_variables:
      DB_ENDPOINT: "${output.dynamodb.endpoint}"
      AUTH_SECRET: "${ssm:/app/auth/secret}"
      
    tags:
      Environment: "production"
      Service: "api-backend"
```

### VPC-Connected Lambda Function

```yaml
lambda:
  vars:
    region: "us-west-2"
    function_name: "database-processor"
    handler: "db.handler"
    runtime: "nodejs16.x"
    filename: "/tmp/db-processor.zip"
    
    # VPC configuration
    vpc_id: "${output.vpc.vpc_id}"
    subnet_ids:
      - "${output.vpc.private_subnet_ids[0]}"
      - "${output.vpc.private_subnet_ids[1]}"
    
    # Function configuration
    memory_size: 1024
    timeout: 60
    log_retention_days: 30
    
    # Security settings
    kms_key_id: "${output.kms.key_id}"
    custom_policy: |
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "dynamodb:GetItem",
              "dynamodb:PutItem",
              "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:us-west-2:123456789012:table/data-table"
          }
        ]
      }
```

### Event-Driven Lambda with Dead Letter Queue

```yaml
lambda:
  vars:
    region: "us-west-2"
    function_name: "event-processor"
    handler: "events.handler"
    runtime: "nodejs16.x"
    filename: "/tmp/event-processor.zip"
    
    # Dead letter configuration
    dead_letter_target_arn: "${output.sqs.queue_arn}"
    
    # SNS trigger
    sns_source_arn: "${output.sns.topic_arn}"
    
    # Advanced event handling
    configure_event_invoke: true
    maximum_retry_attempts: 3
    maximum_event_age_in_seconds: 120
    on_failure_destination: "${output.sqs.dlq_arn}"
    
    # Lambda alias for deployment strategies
    create_alias: true
    alias_name: "live"
    alias_description: "Production alias"
    publish: true
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | - | yes |
| function_name | Name of the Lambda function | `string` | - | yes |
| handler | Lambda function handler | `string` | - | yes |
| runtime | Lambda function runtime | `string` | `"nodejs16.x"` | no |
| filename | Path to the Lambda function's deployment package | `string` | `null` | no |
| source_code_hash | Base64-encoded SHA256 hash of the package file | `string` | `null` | no |
| s3_bucket | S3 bucket containing the Lambda function's deployment package | `string` | `null` | no |
| s3_key | S3 key of the Lambda function's deployment package | `string` | `null` | no |
| s3_object_version | S3 object version of the Lambda function's deployment package | `string` | `null` | no |
| layers | List of Lambda layer ARNs to attach | `list(string)` | `[]` | no |
| memory_size | Amount of memory in MB for the Lambda function | `number` | `128` | no |
| timeout | Timeout in seconds for the Lambda function | `number` | `3` | no |
| publish | Whether to publish a new Lambda function version | `bool` | `false` | no |
| environment_variables | Environment variables for the Lambda function | `map(string)` | `{}` | no |
| vpc_id | VPC ID for Lambda function | `string` | `null` | no |
| subnet_ids | List of subnet IDs for the Lambda function | `list(string)` | `[]` | no |
| dead_letter_target_arn | ARN of the SQS queue or SNS topic for the dead letter target | `string` | `null` | no |
| tracing_mode | X-Ray tracing mode (PassThrough or Active) | `string` | `null` | no |
| log_retention_days | Number of days to retain Lambda logs | `number` | `7` | no |
| kms_key_id | KMS key ID for log encryption | `string` | `null` | no |
| custom_policy | Custom IAM policy for the Lambda function | `string` | `""` | no |
| api_gateway_source_arn | ARN of the API Gateway that invokes the Lambda function | `string` | `null` | no |
| s3_source_arn | ARN of the S3 bucket that invokes the Lambda function | `string` | `null` | no |
| cloudwatch_source_arn | ARN of the CloudWatch Events rule that invokes the Lambda function | `string` | `null` | no |
| sns_source_arn | ARN of the SNS topic that invokes the Lambda function | `string` | `null` | no |
| configure_event_invoke | Whether to configure event invoke settings | `bool` | `false` | no |
| maximum_retry_attempts | Maximum number of retry attempts for async invocation | `number` | `2` | no |
| maximum_event_age_in_seconds | Maximum age of events in seconds | `number` | `60` | no |
| on_success_destination | ARN of destination resource for successful invocations | `string` | `null` | no |
| on_failure_destination | ARN of destination resource for failed invocations | `string` | `null` | no |
| create_alias | Whether to create an alias for the Lambda function | `bool` | `false` | no |
| alias_name | Name of the Lambda function alias | `string` | `"live"` | no |
| alias_description | Description of the Lambda function alias | `string` | `"Live alias"` | no |
| alias_function_version | Version of the Lambda function to use in the alias | `string` | `"$LATEST"` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_arn | ARN of the Lambda function |
| function_name | Name of the Lambda function |
| function_invoke_arn | Invoke ARN of the Lambda function |
| function_version | Latest published version of the Lambda function |
| role_arn | ARN of the IAM role for the Lambda function |
| role_name | Name of the IAM role for the Lambda function |
| log_group_name | Name of the CloudWatch log group for the Lambda function |
| log_group_arn | ARN of the CloudWatch log group for the Lambda function |
| security_group_id | ID of the security group for the Lambda function (if VPC enabled) |
| alias_arn | ARN of the Lambda function alias (if alias enabled) |
| alias_invoke_arn | Invoke ARN of the Lambda function alias (if alias enabled) |

## Troubleshooting

### Common Issues

| Issue | Possible Causes | Solution |
|-------|----------------|----------|
| Deployment failure | Incorrect source code path or permissions | Verify filename, S3 path, or zip content |
| Execution timeout | Function timeout too short | Increase the timeout value |
| Memory errors | Insufficient function memory | Increase memory_size parameter |
| VPC connectivity issues | Security group or subnet misconfiguration | Check VPC settings and ensure egress rules exist |
| Permission errors | Missing IAM permissions | Review and update custom_policy |
| Cold start performance | VPC connectivity, function size | Use provisioned concurrency, reduce dependencies |
| CloudWatch logs not appearing | Log group issues | Check log_retention_days and KMS settings |
| Event source mapping errors | Incorrect source ARN | Verify the ARN value from the source service |

### Debugging Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name <env>-<function-name>

# View recent logs
aws logs get-log-events --log-group-name /aws/lambda/<env>-<function-name> --limit 10

# Test function invocation
aws lambda invoke --function-name <env>-<function-name> --payload '{}' response.json

# Check IAM role permissions
aws iam list-attached-role-policies --role-name <env>-<function-name>-role

# View execution metrics
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration \
  --start-time $(date -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Average Maximum \
  --dimensions Name=FunctionName,Value=<env>-<function-name>
```

## Best Practices

1. **Security**:
   - Apply least privilege principle for IAM permissions
   - Use KMS encryption for sensitive environment variables
   - Restrict VPC egress rules to specific endpoints
   - Store secrets in Secrets Manager or Parameter Store

2. **Performance**:
   - Appropriately size memory and timeout values
   - Minimize cold starts by avoiding VPC when possible
   - Consider provisioned concurrency for latency-sensitive functions
   - Use Lambda layers for common dependencies

3. **Reliability**:
   - Configure dead letter queues for failed executions
   - Set up appropriate retry policies
   - Use destination configuration for execution tracking
   - Create aliases for production deployments

4. **Monitoring**:
   - Enable X-Ray tracing for request tracking
   - Configure appropriate log retention periods
   - Set up CloudWatch alarms for error rates and duration
   - Use structured logging for better log analysis

5. **Cost Optimization**:
   - Right-size memory allocation
   - Implement efficient code to reduce execution time
   - Clean up unused functions and versions
   - Monitor invocation patterns for optimization opportunities

## Related Resources

- [API Gateway Integration Guide](/docs/api-gateway-integration-guide.md)
- [Secrets Manager Guide](/docs/secrets-manager-guide.md)
- [API Gateway Component](/components/terraform/apigateway/README.md)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Serverless Applications Guide](https://aws.amazon.com/serverless/getting-started/)