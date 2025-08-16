# API Gateway Component

_Last Updated: February 27, 2025_

A versatile AWS API Gateway component for Atmos that creates and manages REST and HTTP APIs, including authentication, custom domains, and integrations with various backends.

## Overview

This component creates AWS API Gateway resources including:

- REST API or HTTP API types
- Custom domain names with ACM certificates
- Various authentication methods (Cognito, Lambda, JWT)
- API key and usage plan management
- Integration with Lambda, HTTP endpoints, and other AWS services
- Logging and monitoring configurations
- CloudWatch dashboards

## Usage

### Basic REST API Usage

```yaml
# catalog/apigateway.yaml
name: apigateway
description: "API Gateway configuration"

components:
  terraform:
    apigateway:
      metadata:
        component: apigateway
      vars:
        region: ${region}
        api_name: "${tenant}-${environment}-api"
        api_type: "REST"
        endpoint_type: ["REGIONAL"]
        description: "REST API for ${environment} environment"
        
        # Stage configuration
        stage_name: "${environment}"
        
        # Authentication
        authorizer_type: "COGNITO_USER_POOLS"
        cognito_user_pool_arns: ["${cognito_user_pool_arn}"]
        
        # Logging
        enable_logging: true
        log_retention_days: 30
        
        # API Key and Usage Plan
        create_api_key: true
        create_usage_plan: true
```

### HTTP API Configuration

```yaml
# catalog/apigateway-http.yaml
name: apigateway-http
description: "HTTP API Gateway configuration"

components:
  terraform:
    apigateway:
      metadata:
        component: apigateway
      vars:
        region: ${region}
        api_name: "${tenant}-${environment}-http-api"
        api_type: "HTTP"
        description: "HTTP API for ${environment} environment"
        
        # CORS configuration
        cors_configuration:
          allow_origins: ["*"]
          allow_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
          allow_headers: ["Content-Type", "Authorization"]
          expose_headers: []
          max_age: 300
          allow_credentials: false
        
        # JWT Authorization
        authorizer_type: "JWT"
        jwt_audience: ["${cognito_client_id}"]
        jwt_issuer: "https://cognito-idp.${region}.amazonaws.com/${cognito_user_pool_id}"
```

### Environment-specific configuration

```yaml
# account/dev/us-east-1/apigateway.yaml
import:
  - catalog/apigateway

vars:
  account: dev
  environment: us-east-1
  region: us-east-1
  tenant: mycompany
  
  # API Gateway resources and methods
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
  
  # Lambda integrations
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
  
  # Custom domain
  domain_name: "api.dev.mycompany.com"
  certificate_arn: "${output.acm.certificate_arn}"
  zone_id: "${output.dns.zone_id}"
  
  # Helper mapping for resource IDs
  resource_ids:
    users: "${output.apigateway.rest_api_id}/resources/users"
    items: "${output.apigateway.rest_api_id}/resources/items"

# Dependencies
dependencies:
  - lambda
  - acm
  - dns
  - cognito

# Tags
tags:
  Environment: "Development"
  Team: "API Team"
  CostCenter: "API-1234"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `region` | AWS region | `string` | - | Yes |
| `assume_role_arn` | ARN of the IAM role to assume | `string` | `null` | No |
| `enabled` | Whether to create the resources | `bool` | `true` | No |
| `api_name` | Name of the API Gateway | `string` | - | Yes |
| `api_type` | Type of API Gateway (REST or HTTP) | `string` | `"REST"` | No |
| `description` | Description of the API Gateway | `string` | `"API Gateway managed by Terraform"` | No |
| `endpoint_type` | List of endpoint types | `list(string)` | `["REGIONAL"]` | No |
| `stage_name` | Name of the API Gateway stage | `string` | `"v1"` | No |
| `auto_deploy` | Whether to auto deploy the API (HTTP API only) | `bool` | `true` | No |
| `domain_name` | Custom domain name for the API Gateway | `string` | `null` | No |
| `certificate_arn` | ACM certificate ARN for the custom domain | `string` | `null` | No |
| `base_path` | Base path mapping for the custom domain | `string` | `null` | No |
| `zone_id` | Route53 zone ID for the custom domain | `string` | `null` | No |
| `enable_logging` | Whether to enable CloudWatch logging | `bool` | `true` | No |
| `log_format` | Log format for CloudWatch logs | `string` | `"{ \"requestId\":\"$context.requestId\", ... }"` | No |
| `log_retention_days` | Number of days to retain logs | `number` | `7` | No |
| `cors_configuration` | CORS configuration for HTTP API | `object` | See defaults | No |
| `authorizer_type` | Type of authorizer | `string` | `null` | No |
| `authorizer_identity_source` | Source of identity in request | `string` | `"method.request.header.Authorization"` | No |
| `cognito_user_pool_arns` | List of Cognito user pool ARNs | `list(string)` | `[]` | No |
| `jwt_audience` | List of JWT audience values | `list(string)` | `[]` | No |
| `jwt_issuer` | URL of JWT issuer | `string` | `null` | No |
| `api_resources` | List of API resources to create | `list(object)` | `[]` | No |
| `api_methods` | List of API methods to create | `list(object)` | `[]` | No |
| `api_integrations` | List of API integrations to create | `list(object)` | `[]` | No |
| `create_dashboard` | Whether to create a CloudWatch dashboard | `bool` | `false` | No |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `rest_api_id` | ID of the REST API |
| `rest_api_arn` | ARN of the REST API |
| `rest_api_execution_arn` | Execution ARN of the REST API |
| `rest_api_root_resource_id` | Resource ID of the REST API's root resource |
| `rest_api_stage_name` | Name of the REST API stage |
| `rest_api_stage_arn` | ARN of the REST API stage |
| `http_api_id` | ID of the HTTP API |
| `http_api_arn` | ARN of the HTTP API |
| `http_api_execution_arn` | Execution ARN of the HTTP API |
| `http_api_stage_id` | ID of the HTTP API stage |
| `rest_api_domain_name` | Custom domain name for the REST API |
| `rest_api_domain_name_regional_domain_name` | Regional domain name for the REST API custom domain |
| `http_api_domain_name` | Custom domain name for the HTTP API |
| `api_key_id` | ID of the API key |
| `api_key_value` | Value of the API key (sensitive) |
| `usage_plan_id` | ID of the usage plan |
| `rest_api_authorizer_id` | ID of the REST API authorizer |
| `http_api_authorizer_id` | ID of the HTTP API authorizer |
| `log_group_name` | Name of the CloudWatch log group |
| `domain_name_route53_record` | Route53 record for the custom domain |

## Features

### API Types

The component supports both REST and HTTP API types:

```yaml
# REST API (more features, higher cost)
api_type: "REST"

# HTTP API (simpler, lower cost, JWT auth)
api_type: "HTTP"
```

### Authentication Methods

Configure different authentication methods:

```yaml
# Cognito User Pools (REST API)
authorizer_type: "COGNITO_USER_POOLS"
cognito_user_pool_arns: ["arn:aws:cognito-idp:region:account:userpool/pool-id"]

# Lambda Authorizer (REST API)
authorizer_type: "TOKEN"
lambda_authorizer_uri: "arn:aws:apigateway:region:lambda:path/2015-03-31/functions/arn:aws:lambda:region:account:function:authorizer/invocations"

# JWT Authorizer (HTTP API)
authorizer_type: "JWT"
jwt_audience: ["client-id"]
jwt_issuer: "https://cognito-idp.region.amazonaws.com/user-pool-id"
```

### Custom Domain Setup

```yaml
# Custom domain configuration
domain_name: "api.example.com"
certificate_arn: "arn:aws:acm:region:account:certificate/cert-id"
zone_id: "Z1234567890ABCDEFGHIJ"
```

### API Resources and Methods

```yaml
# Define API resources
api_resources:
  - path_part: "users"
  - path_part: "products"
    parent_id: "parent-resource-id"  # Optional, defaults to root

# Define API methods
api_methods:
  - resource_id: "resource-id"
    http_method: "GET"
    authorization: "COGNITO_USER_POOLS"
  - resource_id: "resource-id"
    http_method: "POST"
    authorization: "NONE"
    api_key_required: true
```

### API Integrations

```yaml
# Lambda integration
api_integrations:
  - resource_id: "resource-id"
    http_method: "GET"
    integration_http_method: "POST"
    type: "AWS_PROXY"
    uri: "arn:aws:apigateway:region:lambda:path/2015-03-31/functions/lambda-arn/invocations"

# HTTP integration
api_integrations:
  - resource_id: "resource-id"
    http_method: "GET"
    integration_http_method: "GET"
    type: "HTTP_PROXY"
    uri: "https://example.com/api"
    
# VPC Link integration
api_integrations:
  - resource_id: "resource-id"
    http_method: "GET"
    integration_http_method: "GET"
    type: "HTTP_PROXY"
    uri: "http://internal-nlb.internal/api"
    connection_type: "VPC_LINK"
    connection_id: "vpc-link-id"
```

## Architecture

This diagram shows the architecture created by this component:

```
                            +---------------+
                            |  DNS Record   |
                            +-------+-------+
                                    |
                            +-------+-------+
                            | Custom Domain |
                            +-------+-------+
                                    |
                         +----------+-----------+
                         |                      |
                 +-------+-------+      +-------+-------+
                 |   REST API    |      |   HTTP API    |
                 +-------+-------+      +-------+-------+
                         |                      |
+-------------------------------------------------------------------+
|                                                                   |
|  +-------------------+    +-------------------+    +------------+ |
|  | Cognito           |    | Lambda            |    | JWT        | |
|  | Authorizer        |    | Authorizer        |    | Authorizer | |
|  +-------------------+    +-------------------+    +------------+ |
|                                                                   |
|  +-------------------+    +-------------------+    +------------+ |
|  | API Methods &     |    | API Methods &     |    | Routes &   | |
|  | Resources         |    | Resources         |    | Integrations |
|  +-------------------+    +-------------------+    +------------+ |
|                                                                   |
|  +-------------------+    +-------------------+                   |
|  | API Key &         |    | CloudWatch        |                   |
|  | Usage Plan        |    | Logs              |                   |
|  +-------------------+    +-------------------+                   |
|                                                                   |
+-------------------------------------------------------------------+
                         |                      |
                 +-------+-------+      +-------+-------+
                 |     Lambda    |      |  HTTP Endpoint |
                 +---------------+      +---------------+
```

## Best Practices

- Use the appropriate API type for your needs (REST for complex APIs, HTTP for simpler APIs)
- Always enable logging for production API Gateways
- Use custom domains for professional API endpoints
- Implement proper authorization for all non-public endpoints
- Create specific IAM roles with least privilege for Lambda integrations
- Use API keys and usage plans to manage and throttle API consumers
- Set up monitoring and alerts for API error rates and latency
- Use resource tagging for cost allocation

## Examples

### REST API with Lambda Integration

```yaml
vars:
  api_type: "REST"
  endpoint_type: ["REGIONAL"]
  
  # API Resources and Methods
  api_resources:
    - path_part: "users"
  
  api_methods:
    - resource_id: "${resource_ids.users}"
      http_method: "GET"
      authorization: "COGNITO_USER_POOLS"
    - resource_id: "${resource_ids.users}"
      http_method: "POST"
      authorization: "COGNITO_USER_POOLS"
  
  # Lambda Integrations
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
  
  # Cognito Authorization
  authorizer_type: "COGNITO_USER_POOLS"
  cognito_user_pool_arns: ["${output.cognito.user_pool_arn}"]
```

### HTTP API with JWT Authorization

```yaml
vars:
  api_type: "HTTP"
  
  # CORS Configuration
  cors_configuration:
    allow_origins: ["https://app.example.com"]
    allow_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers: ["Content-Type", "Authorization"]
    expose_headers: ["Content-Length", "X-Request-Id"]
    max_age: 3600
    allow_credentials: true
  
  # JWT Authorization
  authorizer_type: "JWT"
  jwt_audience: ["${output.cognito.user_pool_client_id}"]
  jwt_issuer: "https://cognito-idp.${region}.amazonaws.com/${output.cognito.user_pool_id}"
```

## Related Components

- **lambda** - For creating Lambda functions to integrate with API Gateway
- **acm** - For creating SSL/TLS certificates for custom domains
- **dns** - For creating DNS records for custom domains
- **cognito** - For creating user pools for authentication
- **monitoring** - For creating CloudWatch dashboards and alarms

## Troubleshooting

### Common Issues

1. **Deployment Fails with "Invalid Resource Path"**: Ensure resource path matches exactly
   
   ```bash
   # Check API resources
   aws apigateway get-resources --rest-api-id <api-id>
   ```

2. **CORS Issues in Browser**: Ensure CORS configuration includes required headers
   
   ```yaml
   cors_configuration:
     allow_origins: ["*"]  # More specific for production
     allow_methods: ["*"]
     allow_headers: ["*"]
   ```

3. **Lambda Integration 5XX Errors**: Check Lambda permissions
   
   ```bash
   # Ensure Lambda function policy allows API Gateway
   aws lambda get-policy --function-name <function-name>
   ```

### Validation Commands

```bash
# Validate API Gateway configuration
atmos terraform validate apigateway -s mycompany-dev-us-east-1

# View Terraform plan
atmos terraform plan apigateway -s mycompany-dev-us-east-1

# Check component outputs after deployment
atmos terraform output apigateway -s mycompany-dev-us-east-1
```

### Testing the API

```bash
# Get the API URL
API_URL=$(atmos terraform output apigateway.rest_api_domain_name -s mycompany-dev-us-east-1)

# Test with curl
curl -H "Authorization: Bearer <token>" https://$API_URL/users
```