# API Gateway Example

This example demonstrates how to implement a secure API Gateway with Lambda integrations, custom domain, and Cognito authentication using the Atmos framework.

## Architecture

This API Gateway configuration implements:

- REST API with Lambda function integrations
- Cognito user pool for authentication
- Custom domain with ACM certificate
- API keys and usage plans for API management
- CloudWatch logging and monitoring
- WAF integration for security

## Files

- `catalog-apigateway.yaml` - Catalog entry for the API Gateway component
- `dev-apigateway.yaml` - Development environment API Gateway configuration
- `catalog-lambda.yaml` - Catalog entry for the Lambda function component
- `dev-lambda.yaml` - Development environment Lambda configuration

## Implementation

### Catalog Configuration

```yaml
# API Gateway catalog configuration (catalog/apigateway.yaml)
name: apigateway
description: "REST API Gateway configuration"

components:
  terraform:
    apigateway:
      metadata:
        component: apigateway
        type: abstract
      vars:
        enabled: true
        region: ${region}
        api_name: "${tenant}-${environment}-api"
        description: "REST API for ${environment} environment"
        api_type: "REST"
        endpoint_type: ["REGIONAL"]
        
        # REST API specific configurations
        binary_media_types:
          - "application/octet-stream"
          - "image/*"
        minimum_compression_size: 10240
        
        # Authorization
        authorizer_type: "COGNITO_USER_POOLS"
        cognito_user_pool_arns: ["${cognito_user_pool_arn}"]
        authorizer_identity_source: "method.request.header.Authorization"
        
        # API Gateway access logging
        enable_logging: true
        log_format: "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"resourcePath\":\"$context.resourcePath\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\", \"integrationError\":\"$context.integrationErrorMessage\" }"
        log_retention_days: 30
        
        # Stage configurations
        stage_name: "${environment}"
        
        # API Keys and Usage Plans
        create_api_key: true
        create_usage_plan: true
        usage_plan_quota_limit: 10000
        usage_plan_quota_period: "MONTH"
        usage_plan_throttle_burst_limit: 100
        usage_plan_throttle_rate_limit: 50
        
        # Monitoring
        create_dashboard: true
        tracing_enabled: true

      # Define common tags
      tags:
        Tenant: ${tenant}
        Account: ${account}
        Environment: ${environment}
        Component: "ApiGateway"
        ManagedBy: "Terraform"
```

### Environment Configuration

```yaml
# Development API Gateway configuration (account/dev/dev-us-east-1/apigateway.yaml)
import:
  - catalog/apigateway

vars:
  account: dev
  environment: dev-us-east-1
  region: us-east-1
  tenant: mycompany

  # API Gateway Configuration
  api_name: "${tenant}-${environment}-api"
  api_description: "REST API for ${tenant}-${environment}"
  
  # API Resources and Methods
  api_resources:
    - path_part: "users"
    - path_part: "items"
  
  api_methods:
    - resource_id: "${resource_ids.users}"
      http_method: "GET"
      authorization: "COGNITO_USER_POOLS"
    - resource_id: "${resource_ids.users}"
      http_method: "POST"
      authorization: "COGNITO_USER_POOLS"
    - resource_id: "${resource_ids.items}"
      http_method: "GET"
      authorization: "NONE"
      api_key_required: true
  
  # API Integrations
  api_integrations:
    - resource_id: "${resource_ids.users}"
      http_method: "GET"
      integration_http_method: "POST"
      type: "AWS_PROXY"
      uri: "${output.lambda.function_invoke_arns.get_users}"
    - resource_id: "${resource_ids.users}"
      http_method: "POST"
      integration_http_method: "POST"
      type: "AWS_PROXY"
      uri: "${output.lambda.function_invoke_arns.create_user}"
    - resource_id: "${resource_ids.items}"
      http_method: "GET"
      integration_http_method: "POST"
      type: "AWS_PROXY"
      uri: "${output.lambda.function_invoke_arns.get_items}"
  
  # Domain Configuration
  domain_name: "api.${environment}.${tenant}.com"
  certificate_arn: "${output.acm.certificate_arn}"
  
  # Route53 Configuration
  zone_id: "${output.dns.zone_id}"
  
  # Cognito Authorizer
  cognito_user_pool_arn: "${output.cognito.user_pool_arn}"
  
  # Resource IDs mapping for easy referencing
  resource_ids:
    users: "${output.apigateway.rest_api_id}/resources/users"
    items: "${output.apigateway.rest_api_id}/resources/items"
  
# Dependencies on other components
dependencies:
  - lambda
  - acm
  - dns
  - cognito

# Additional tags
tags:
  Team: "API Team"
  CostCenter: "IT"
  Project: "API Gateway"
  Environment: "Development"
```

## Usage

1. Copy the catalog configuration to `stacks/catalog/apigateway.yaml`
2. Copy the environment configuration to `stacks/account/dev/your-environment/apigateway.yaml`
3. Ensure you have the dependencies (lambda, acm, dns, cognito) deployed
4. Customize the configurations as needed
5. Deploy using Atmos:

```bash
# Validate the configuration
atmos terraform validate apigateway -s mycompany-dev-dev-us-east-1

# Plan the deployment
atmos terraform plan apigateway -s mycompany-dev-dev-us-east-1

# Apply the changes
atmos terraform apply apigateway -s mycompany-dev-dev-us-east-1
```

## Lambda Function Example

For the Lambda functions referenced in the API Gateway configuration:

```yaml
# Lambda catalog configuration (catalog/lambda.yaml)
name: lambda
description: "Lambda functions"

components:
  terraform:
    lambda:
      metadata:
        component: lambda
        type: abstract
      vars:
        enabled: true
        region: ${region}
        
        # Lambda functions configuration
        functions:
          get_users:
            name: "${tenant}-${environment}-get-users"
            description: "Get users function"
            handler: "index.handler"
            runtime: "nodejs18.x"
            memory_size: 128
            timeout: 30
            environment_variables:
              ENVIRONMENT: "${environment}"
              TABLE_NAME: "${tenant}-${environment}-users"
          create_user:
            name: "${tenant}-${environment}-create-user"
            description: "Create user function"
            handler: "index.handler"
            runtime: "nodejs18.x"
            memory_size: 128
            timeout: 30
            environment_variables:
              ENVIRONMENT: "${environment}"
              TABLE_NAME: "${tenant}-${environment}-users"
          get_items:
            name: "${tenant}-${environment}-get-items"
            description: "Get items function"
            handler: "index.handler"
            runtime: "nodejs18.x"
            memory_size: 128
            timeout: 30
            environment_variables:
              ENVIRONMENT: "${environment}"
              TABLE_NAME: "${tenant}-${environment}-items"
        
        # Common Lambda settings
        create_role: true
        enable_cloudwatch_logs: true
        log_retention_days: 30
```

## Best Practices

This example implements these AWS best practices:

1. **Authentication** - Secure APIs with Cognito authentication
2. **API Management** - API keys and usage plans for rate limiting
3. **Monitoring** - CloudWatch logs and custom dashboard
4. **Security** - WAF integration and proper authorization
5. **Custom Domain** - Professional domain name with HTTPS

## Customization Options

- **Authentication**: Switch between Cognito, Lambda authorizers, or JWT
- **API Type**: Change from REST to HTTP API for simpler, lower-cost APIs
- **Integrations**: Modify Lambda integrations or add other integration types
- **Throttling**: Adjust usage plan settings for different API consumers
- **Security**: Add WAF rules and IP-based restrictions
- **Resources & Methods**: Add more API resources and methods as needed