# API Gateway Integration in Atmos
> *Scalable and secure API management for multi-account AWS environments*

## Table of Contents

- [Introduction](#introduction)
- [Configuration Options](#configuration-options)
- [Authentication Methods](#authentication-methods)
- [Lambda Integration](#lambda-integration)
- [VPC Link Integration](#vpc-link-integration)
- [Custom Domain Setup](#custom-domain-setup)
- [Monitoring and Logging](#monitoring-and-logging)
- [Performance Optimization](#performance-optimization)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Appendix: Reference](#appendix-reference)

## Introduction

The Amazon API Gateway component for Atmos provides a comprehensive solution for creating, publishing, maintaining, and securing APIs at any scale. It supports both REST and HTTP APIs with a variety of integration types, authentication methods, and monitoring capabilities.

**Key Benefits:**
- **Unified API Management** - Central control of API resources across environments
- **Flexible Integration Options** - Support for Lambda, HTTP, AWS services, and private resources
- **Advanced Security Controls** - Multiple authentication and authorization options
- **Performance at Scale** - Built-in caching, throttling, and monitoring
- **Cost Optimization** - Granular control over API usage and resource allocation

## Configuration Options

### REST vs. HTTP APIs

API Gateway offers two main API types with different features and pricing models:

| Feature | REST API | HTTP API |
|---------|----------|----------|
| **Base Path Mapping** | ✅ | ✅ |
| **Custom Domain Names** | ✅ | ✅ |
| **API Keys** | ✅ | ❌ |
| **Usage Plans** | ✅ | ❌ |
| **Throttling/Quotas** | ✅ | ✅ (Limited) |
| **Request Validation** | ✅ | ❌ |
| **Request/Response Transformations** | ✅ | ❌ |
| **WAF Integration** | ✅ | ✅ |
| **Private APIs** | ✅ | ✅ |
| **JWT Authorizers** | Limited | ✅ |
| **CORS Support** | Manual | Automatic |
| **OpenAPI Support** | 3.0 | 3.0 |
| **Latency** | Higher | Lower |
| **Cost** | Higher | Lower |

```yaml
# REST API Configuration
apigateway:
  api_type: "REST"
  name: "${tenant}-${environment}-api"
  description: "REST API for ${environment} environment"
  endpoint_type: "REGIONAL"
  binary_media_types: ["application/octet-stream", "image/*"]
  minimum_compression_size: 10240
  enable_api_gateway_logs: true
  api_key_source: "HEADER"
```

```yaml
# HTTP API Configuration
apigateway:
  api_type: "HTTP"
  name: "${tenant}-${environment}-api"
  description: "HTTP API for ${environment} environment"
  cors_configuration:
    allow_origins: ["*"]
    allow_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers: ["Content-Type", "Authorization"]
    max_age: 300
  enable_api_gateway_logs: true
```

**Recommended for:**
- **REST API:** Complex APIs requiring request validation, transformation, API keys, or detailed throttling
- **HTTP API:** Simple APIs prioritizing lower latency and cost, requiring JWT authorization

## Authentication Methods

### API Keys and Usage Plans

For REST APIs, you can implement metered access through API keys and usage plans:

```yaml
# API Keys Configuration
api_keys:
  default:
    name: "${tenant}-${environment}-default-key"
    description: "Default API key for ${environment}"
    enabled: true
    
usage_plans:
  basic:
    name: "${tenant}-${environment}-basic"
    description: "Basic usage plan with rate limiting"
    quota_settings:
      limit: 1000
      period: "MONTH"
    throttle_settings:
      burst_limit: 20
      rate_limit: 10
    api_stages:
      - api_id: ${api_id}
        stage: ${environment}
```

### Cognito User Pools

Integrate with Amazon Cognito for user authentication:

```yaml
# Cognito Authorizer Configuration
authorizers:
  cognito:
    name: "cognito-authorizer"
    type: "COGNITO_USER_POOLS"
    provider_arns: ["${output.cognito.user_pool_arn}"]
    identity_source: "method.request.header.Authorization"
```

### Lambda Authorizers

Custom authorization logic using Lambda functions:

```yaml
# Lambda Authorizer Configuration
authorizers:
  custom:
    name: "lambda-authorizer"
    type: "TOKEN"
    authorizer_uri: "${output.lambda.authorizer_function_invoke_arn}"
    authorizer_credentials: "${output.iam.authorizer_role_arn}"
    identity_source: "method.request.header.Authorization"
    cache_ttl_in_seconds: 300
```

### JWT Authorizers (HTTP APIs)

For HTTP APIs, JWT-based authorization is available:

```yaml
# JWT Authorizer for HTTP APIs
jwt_authorizers:
  amazon:
    name: "cognito-jwt"
    identity_source: "$request.header.Authorization"
    audience: ["${output.cognito.user_pool_client_id}"]
    issuer: "https://cognito-idp.${region}.amazonaws.com/${output.cognito.user_pool_id}"
```

## Lambda Integration

### REST API Lambda Integration

```yaml
# REST API with Lambda Integrations
resources:
  users:
    path_part: "users"
    methods:
      GET:
        authorization_type: "COGNITO_USER_POOLS"
        authorizer_id: "cognito"
        integration:
          type: "AWS_PROXY"
          uri: "${output.lambda.get_users_function_invoke_arn}"
          integration_http_method: "POST"
      POST:
        authorization_type: "COGNITO_USER_POOLS"
        authorizer_id: "cognito"
        integration:
          type: "AWS_PROXY"
          uri: "${output.lambda.create_user_function_invoke_arn}"
          integration_http_method: "POST"
  users_item:
    path_part: "{id}"
    parent_id: "users"
    methods:
      GET:
        authorization_type: "COGNITO_USER_POOLS"
        authorizer_id: "cognito"
        request_parameters:
          method.request.path.id: true
        integration:
          type: "AWS_PROXY"
          uri: "${output.lambda.get_user_function_invoke_arn}"
          integration_http_method: "POST"
```

### HTTP API Lambda Integration

```yaml
# HTTP API with Lambda Integrations
routes:
  - route_key: "GET /users"
    target: "integrations/${output.lambda.get_users_function_id}"
    authorizer_id: "amazon"
  - route_key: "POST /users"
    target: "integrations/${output.lambda.create_user_function_id}"
    authorizer_id: "amazon"
  - route_key: "GET /users/{id}"
    target: "integrations/${output.lambda.get_user_function_id}"
    authorizer_id: "amazon"
```

### Required IAM Permissions

Lambda functions need permission to be invoked by API Gateway:

```yaml
# Permission for Lambda Invocation
lambda_permissions:
  api_gateway:
    statement_id: "AllowAPIGatewayInvoke"
    action: "lambda:InvokeFunction"
    principal: "apigateway.amazonaws.com"
    source_arn: "${output.apigateway.execution_arn}/*/*/*"
```

## VPC Link Integration

For private APIs that need to access resources within a VPC:

### VPC Link Creation

```yaml
# VPC Link for REST API
vpc_links:
  main:
    name: "${tenant}-${environment}-vpc-link"
    target_arns: ["${output.network_load_balancer.arn}"]
    description: "VPC Link for private service integration"
```

```yaml
# VPC Link for HTTP API
http_vpc_links:
  main:
    name: "${tenant}-${environment}-http-vpc-link"
    subnet_ids: ${output.vpc.private_subnet_ids}
    security_group_ids: ["${output.securitygroup.api_sg_id}"]
```

### Integrating with Private Resources

```yaml
# REST API with VPC Link Integration
resources:
  private_service:
    path_part: "private"
    methods:
      GET:
        authorization_type: "COGNITO_USER_POOLS"
        authorizer_id: "cognito"
        integration:
          type: "HTTP_PROXY"
          uri: "http://internal-nlb.${environment}.${tenant}.internal/private"
          integration_http_method: "GET"
          connection_type: "VPC_LINK"
          connection_id: "${vpc_link_id}"
```

```yaml
# HTTP API with VPC Link Integration
routes:
  - route_key: "GET /private"
    target: "integrations/${private_integration_id}"
    authorizer_id: "amazon"

integrations:
  private:
    integration_type: "HTTP_PROXY"
    integration_uri: "http://internal-nlb.${environment}.${tenant}.internal/private"
    integration_method: "GET"
    connection_type: "VPC_LINK"
    connection_id: "${http_vpc_link_id}"
```

## Custom Domain Setup

### ACM Certificate Integration

```yaml
# ACM Certificate for API Gateway
acm:
  metadata:
    component: acm
  vars:
    domain_name: "api.${environment}.${tenant}.com"
    validation_method: "DNS"
    zone_id: "${output.dns.zone_id}"
```

### Domain Configuration

```yaml
# Custom Domain for API Gateway
domain_names:
  main:
    domain_name: "api.${environment}.${tenant}.com"
    certificate_arn: "${output.acm.certificate_arn}"
    security_policy: "TLS_1_2"
    endpoint_type: "REGIONAL"
    domain_name_configuration:
      certificate_arn: "${output.acm.certificate_arn}"
      endpoint_type: "REGIONAL"
      security_policy: "TLS_1_2"
    base_path_mappings:
      # Empty key maps to root (/)
      "": 
        api_id: "${api_id}"
        stage: "${environment}"
```

### Route53 DNS Integration

```yaml
# DNS Records for API Gateway
dns_records:
  api_endpoint:
    zone_name: "main"
    name: "api.${environment}.${tenant}.com"
    type: "A"
    alias:
      name: "${output.apigateway.domain_name_regional_domain_name}"
      zone_id: "${output.apigateway.domain_name_regional_zone_id}"
      evaluate_target_health: true
```

## Monitoring and Logging

### CloudWatch Logging

```yaml
# API Gateway Logging Configuration
api_gateway_logs:
  enabled: true
  log_level: "INFO"  # ERROR, INFO
  data_trace_enabled: true  # Enable full request/response logging
  metrics_enabled: true
  retention_days: 7
```

### CloudWatch Metrics and Alarms

```yaml
# CloudWatch Alarms for API Gateway
monitoring:
  metadata:
    component: monitoring
  vars:
    dashboard_name: "${tenant}-${environment}-api-gateway"
    alarms:
      api_gateway_5xx:
        alarm_name: "${tenant}-${environment}-api-gateway-5xx-errors"
        comparison_operator: "GreaterThanThreshold"
        evaluation_periods: 1
        metric_name: "5XXError"
        namespace: "AWS/ApiGateway"
        period: 60
        statistic: "Sum"
        threshold: 5
        dimensions:
          ApiName: "${api_name}"
          Stage: "${environment}"
        alarm_actions: ["${output.sns.alarm_topic_arn}"]
        ok_actions: ["${output.sns.alarm_topic_arn}"]
```

### X-Ray Tracing

```yaml
# X-Ray Tracing Configuration
tracing:
  enabled: true
  xray_tracing_enabled: true
```

## Performance Optimization

### Caching Strategies

API Gateway offers response caching for improved performance and reduced backend load:

```yaml
# API Gateway Caching
stage_settings:
  cache_data_encrypted: true
  cache_ttl_in_seconds: 300
  caching_enabled: true
  cache_cluster_enabled: true
  cache_cluster_size: "0.5"  # Valid values: 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237
```

### Request Throttling

Control API request rates to protect your backend services:

```yaml
# API Gateway Throttling 
stage_settings:
  throttling_burst_limit: 5000
  throttling_rate_limit: 10000
```

### Regional vs. Edge-Optimized Endpoints

Choose endpoint types based on your API's audience and latency requirements:

```yaml
# Regional Endpoint (default)
endpoint_type: "REGIONAL"  # Best for APIs consumed within the same region

# Edge-Optimized Endpoint
endpoint_type: "EDGE"  # Best for public APIs with global users

# Private Endpoint
endpoint_type: "PRIVATE"  # Best for internal APIs accessed only from VPCs
```

## Security Best Practices

| Best Practice | Implementation |
|--------------|----------------|
| **Implement Authentication** | Use JWT, Cognito, or Lambda authorizers for all non-public endpoints |
| **Enable CloudWatch Logging** | Set `enable_api_gateway_logs: true` with appropriate log level |
| **Use HTTPS Only** | Configure `security_policy: "TLS_1_2"` for all domains |
| **Input Validation** | Enable request validation with JSON Schema validation |
| **Rate Limiting** | Configure throttling limits for all APIs |
| **WAF Integration** | Associate WAF web ACLs with production APIs |
| **Private Endpoints** | Use private APIs for internal services |

### WAF Integration

Protect your APIs from common vulnerabilities with AWS WAF:

```yaml
# WAF Integration
waf_web_acl_association:
  web_acl_arn: "${output.waf.web_acl_arn}"
  resource_arn: "${output.apigateway.stage_arn}"
```

### API Request Validation

Configure request validation to enforce correct request parameters and body:

```yaml
# Request Validation Model
models:
  user:
    name: "UserModel"
    description: "Validation model for user data"
    content_type: "application/json"
    schema: |
      {
        "$schema": "http://json-schema.org/draft-04/schema#",
        "title": "UserModel",
        "type": "object",
        "required": ["name", "email"],
        "properties": {
          "name": { "type": "string" },
          "email": { "type": "string", "format": "email" },
          "age": { "type": "integer", "minimum": 18 }
        }
      }

# Method with Request Validation
methods:
  POST:
    authorization_type: "COGNITO_USER_POOLS"
    authorizer_id: "cognito"
    request_validator_id: "body"
    request_models:
      application/json: "UserModel"
```

## Troubleshooting

### Common Issues and Solutions

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| **403 Forbidden** | Missing or invalid authentication | Check authorization headers, API keys, or token validity |
| **500 Internal Server Error** | Lambda function error, integration issue | Review CloudWatch logs for the integrated Lambda function |
| **CORS errors** | Incorrect CORS configuration | Ensure proper CORS headers are set for OPTIONS requests |
| **Latency issues** | Cold starts, inefficient backend | Enable caching, optimize Lambda functions, monitor with X-Ray |
| **Invalid API signature** | Clock skew, incorrect signature process | Ensure client clock is synced, verify signature process |
| **Integration timeout** | Backend service not responding in time | Increase timeout settings, optimize backend performance |

### Diagnostic Tools

- **CloudWatch Logs** - Review logs for API Gateway and integrated Lambda functions
- **X-Ray Traces** - Analyze request flow and identify bottlenecks
- **CloudWatch Metrics** - Monitor request counts, latency, errors
- **API Gateway Test Console** - Test endpoints directly from the AWS console
- **curl/Postman** - Test API endpoints with custom headers and payloads

## Appendix: Reference

### Variable Reference

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `api_type` | string | Type of API (REST or HTTP) | "REST" |
| `name` | string | Name of the API | (required) |
| `description` | string | Description of the API | "" |
| `endpoint_type` | string | API endpoint type | "REGIONAL" |
| `binary_media_types` | list(string) | Media types to handle as binary | [] |
| `minimum_compression_size` | number | Minimum response size to compress | -1 (disabled) |
| `api_key_source` | string | Location of API key | "HEADER" |
| `cache_cluster_enabled` | bool | Enable caching | false |
| `cache_cluster_size` | string | Cache cluster size | "0.5" |
| `xray_tracing_enabled` | bool | Enable X-Ray tracing | false |

### Integration Matrix

| AWS Service | Integration Type | Notes |
|-------------|------------------|-------|
| **Lambda** | AWS_PROXY | Simplest integration, Lambda handles request/response mapping |
| **Lambda** | AWS | Custom request/response mapping with VTL templates |
| **HTTP/ALB** | HTTP_PROXY | Direct proxy to HTTP endpoints |
| **HTTP/ALB** | HTTP | Custom request/response mapping with VTL templates |
| **AWS Service** | AWS | Direct integration with AWS services like SQS, SNS, etc. |
| **Mock** | MOCK | Generate responses directly from API Gateway |

### Further Reading

1. [AWS API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html)
2. [API Gateway Security Best Practices](https://docs.aws.amazon.com/whitepapers/latest/serverless-architectures-api-gateway/security.html)
3. [Optimizing API Gateway Performance](https://aws.amazon.com/blogs/compute/optimizing-api-gateway-performance/)
4. [AWS API Gateway Multi-Region Deployments](https://aws.amazon.com/blogs/compute/building-a-multi-region-serverless-application-with-amazon-api-gateway-and-aws-lambda/)