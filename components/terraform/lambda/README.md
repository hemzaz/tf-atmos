# Lambda Component

This component creates and manages AWS Lambda functions and related resources.

## Usage

```hcl
component "lambda" {
  instance = "api-backend"
  
  vars = {
    region = "us-west-2"
    
    functions = {
      "api-handler" = {
        function_name = "api-handler"
        description   = "API request handler for the backend"
        runtime       = "nodejs18.x"
        handler       = "index.handler"
        memory_size   = 256
        timeout       = 30
        
        source_code = {
          s3_bucket        = "my-lambda-code-bucket" 
          s3_key           = "functions/api-handler.zip"
          source_code_hash = "..."  # Output of filebase64sha256()
        }
        
        environment_variables = {
          NODE_ENV     = "production"
          DB_ENDPOINT  = "..."
          LOG_LEVEL    = "info"
        }
        
        # Optional VPC configuration
        vpc_config = {
          subnet_ids         = ["subnet-abcd1234", "subnet-efgh5678"]
          security_group_ids = ["sg-abcd1234"]
        }
        
        # Optional permissions
        iam_policy_documents = [
          jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect   = "Allow"
                Action   = ["s3:GetObject"]
                Resource = "arn:aws:s3:::my-bucket/*"
              }
            ]
          })
        ]
        
        # Optional triggers/event sources
        event_sources = {
          "sqs" = {
            event_source_arn    = "arn:aws:sqs:us-west-2:123456789012:my-queue"
            batch_size          = 10
            maximum_retry_count = 2
          }
        }
      }
    }
    
    # Common tags for all resources
    tags = {
      Environment = "dev"
      Owner       = "platform-team"
      Terraform   = "true"
    }
  }
}
```

## Features

- Create and manage Lambda functions with comprehensive configuration options
- Support for multiple functions within a single component
- Environment variables management
- IAM role and policy configuration for functions
- Event source mappings (SQS, DynamoDB, Kinesis, etc.)
- VPC integration
- CloudWatch log group configuration
- Provisioned concurrency settings

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| functions | Map of Lambda function configurations | `map(object)` | `{}` | no |
| layer_arns | Map of Lambda layer ARNs to attach to functions | `map(list(string))` | `{}` | no |
| log_retention_days | Number of days to retain Lambda logs | `number` | `30` | no |
| tags | Common tags for all resources | `map(string)` | `{}` | no |

### Lambda Function Configuration

Each function in the `functions` map supports the following attributes:

```hcl
{
  function_name        = string
  description          = optional(string)
  handler              = string
  runtime              = string
  memory_size          = optional(number, 128)
  timeout              = optional(number, 3)
  reserved_concurrent_executions = optional(number)
  
  # Source code options
  source_code = object({
    s3_bucket        = optional(string)
    s3_key           = optional(string)
    s3_object_version = optional(string)
    source_code_hash = optional(string)
    filename         = optional(string)
    image_uri        = optional(string)
    image_config     = optional(map(string))
  })
  
  # Environment variables
  environment_variables = optional(map(string), {})
  
  # VPC configuration
  vpc_config = optional(object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  }))
  
  # Dead letter configuration
  dead_letter_config = optional(object({
    target_arn = string
  }))
  
  # Tracing config
  tracing_config = optional(object({
    mode = string
  }))
  
  # IAM permissions
  iam_policy_documents = optional(list(string), [])
  
  # Event sources
  event_sources = optional(map(object({
    event_source_arn    = string
    starting_position   = optional(string)
    batch_size          = optional(number)
    maximum_retry_count = optional(number)
    parallelization_factor = optional(number)
    maximum_record_age_in_seconds = optional(number)
  })), {})
  
  # Tags specific to this function
  tags = optional(map(string), {})
}
```

## Outputs

| Name | Description |
|------|-------------|
| function_arns | Map of function ARNs |
| function_names | Map of function names |
| function_roles | Map of IAM role ARNs for functions |
| invoke_arns | Map of Lambda function invoke ARNs |
| log_group_arns | Map of CloudWatch log group ARNs |

## Example: API Handler with SQS Integration

```hcl
component "lambda" {
  instance = "api-handlers"
  
  vars = {
    region = "us-west-2"
    
    functions = {
      "process-order" = {
        function_name = "process-order"
        description   = "Processes new orders from SQS queue"
        runtime       = "nodejs18.x"
        handler       = "index.handler"
        memory_size   = 512
        timeout       = 60
        
        source_code = {
          filename = "process-order.zip"
        }
        
        environment_variables = {
          ORDER_TABLE = "orders"
          REGION      = "us-west-2"
        }
        
        event_sources = {
          "orders-queue" = {
            event_source_arn = "arn:aws:sqs:us-west-2:123456789012:orders-queue"
            batch_size       = 10
          }
        }
      }
    }
    
    tags = {
      Environment = "production"
      Service     = "orders"
    }
  }
}
```

## Best Practices

1. Always set appropriate memory and timeout values
2. Use the principle of least privilege for IAM permissions
3. Set appropriate log retention periods
4. Consider VPC access only when needed
5. Use environment variables for configuration
6. Implement proper error handling and dead letter queues