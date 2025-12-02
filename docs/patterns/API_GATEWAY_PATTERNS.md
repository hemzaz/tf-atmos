# API Gateway Patterns

## Overview

The API Gateway pattern provides enterprise-grade API management using AWS API Gateway with multiple protocol support (REST, HTTP, WebSocket). This pattern includes authentication via Cognito, WAF protection, custom domains, usage plans, and comprehensive observability.

## Architecture Diagram

```
                     +-------------------+
                     |   Clients         |
                     |   (Web, Mobile,   |
                     |   Partners)       |
                     +--------+----------+
                              |
                              | HTTPS
                              v
                     +--------+----------+
                     |   Route53         |
                     |   (DNS)           |
                     +--------+----------+
                              |
                              v
                     +--------+----------+
                     |   ACM Certificate |
                     |   (TLS/SSL)       |
                     +--------+----------+
                              |
                              v
                     +--------+----------+
                     |   WAF             |
                     |   (Protection)    |
                     +--------+----------+
                              |
              +---------------+---------------+
              |               |               |
              v               v               v
      +-------+------+ +------+------+ +------+------+
      |  REST API    | | HTTP API    | | WebSocket   |
      |  Gateway     | | Gateway     | | API         |
      +--------------+ +-------------+ +-------------+
              |               |               |
              v               v               v
      +-------+------+ +------+------+ +------+------+
      |  Cognito     | | JWT         | | Lambda      |
      |  Authorizer  | | Authorizer  | | Authorizer  |
      +--------------+ +-------------+ +-------------+
              |               |               |
              +-------+-------+-------+-------+
                      |               |
                      v               v
              +-------+------+ +------+------+
              |  Lambda      | | VPC Link    |
              |  Functions   | | (Private)   |
              +--------------+ +-------------+
                      |               |
                      v               v
              +-------+------+ +------+------+
              |  DynamoDB    | | Private     |
              |  (Data)      | | Services    |
              +--------------+ +-------------+
```

## API Types Comparison

| Feature | REST API | HTTP API | WebSocket API |
|---------|----------|----------|---------------|
| **Cost** | $3.50/million | $1.00/million | $1.00/million messages |
| **Latency** | ~29ms | ~10ms | N/A |
| **Use Case** | Full-featured APIs | Simple APIs, proxies | Real-time apps |
| **Auth Options** | Cognito, Lambda, IAM, API Key | JWT, Lambda, IAM | Lambda, IAM |
| **Caching** | Yes | No | No |
| **Request Validation** | Yes | No | No |
| **Request Transformation** | Yes | Limited | No |
| **Usage Plans** | Yes | No | No |
| **WAF Support** | Yes | No | No |
| **Private Integrations** | VPC Link | VPC Link | No |

## Components

### API Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| REST API Gateway | Full-featured REST API | Complex APIs with caching, transformation |
| HTTP API Gateway | Lightweight HTTP proxy | Simple APIs, cost-sensitive workloads |
| WebSocket API | Persistent connections | Real-time bidirectional communication |
| Custom Domain | api.example.com | Branded API endpoints |
| Base Path Mapping | /v1, /v2 | API versioning |

### Security Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| WAF | Web Application Firewall | SQL injection, XSS, rate limiting |
| Cognito | User authentication | JWT tokens, OAuth2 flows |
| API Keys | Client identification | Usage tracking, throttling |
| Usage Plans | Rate limiting | Quota management |

### Integration Layer

| Component | Description | Purpose |
|-----------|-------------|---------|
| Lambda Integration | Serverless handlers | API business logic |
| VPC Link | Private connectivity | Access internal services |
| Service Integration | Direct AWS calls | DynamoDB, SQS, etc. |

## Deployment

### Prerequisites

- AWS Account with appropriate permissions
- Route53 hosted zone for custom domain
- Atmos CLI installed and configured

### Deploy the Pattern

```bash
# Plan the deployment
atmos workflow plan-api-gateway -f patterns.yaml stack=<tenant>-<environment>

# Deploy all components
atmos workflow deploy-api-gateway -f patterns.yaml stack=<tenant>-<environment>

# Validate deployment
atmos workflow validate-pattern -f patterns.yaml pattern=api-gateway stack=<tenant>-<environment>
```

### Environment-Specific Configurations

#### Development
- WAF disabled (cost savings)
- Short log retention (7 days)
- No API caching
- Higher free tier quotas

#### Staging
- WAF enabled
- Moderate log retention (14 days)
- Standard quotas

#### Production
- WAF enabled with full ruleset
- Extended log retention (90 days)
- API caching enabled
- Provisioned concurrency for Lambda
- Strict quotas

## API Design

### REST API Example

```yaml
# OpenAPI 3.0 Specification
openapi: '3.0.1'
info:
  title: 'User API'
  version: '1.0.0'
paths:
  /users:
    get:
      summary: List users
      security:
        - cognito: []
      x-amazon-apigateway-integration:
        type: aws_proxy
        httpMethod: POST
        uri: arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/${lambda_arn}/invocations
    post:
      summary: Create user
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateUser'
      x-amazon-apigateway-request-validator: validate-all
```

### HTTP API Example

```yaml
routes:
  - route_key: "GET /items"
    integration_type: "AWS_PROXY"
    integration_uri: "${lambda_invoke_arn}"
    authorization_type: "JWT"
    authorizer_id: "${jwt_authorizer_id}"
```

### WebSocket API Example

```yaml
routes:
  $connect:
    integration: "lambda:connect-handler"
  $disconnect:
    integration: "lambda:disconnect-handler"
  sendmessage:
    integration: "lambda:message-handler"
  subscribe:
    integration: "lambda:subscribe-handler"
```

## Authentication Patterns

### Cognito User Pools (REST API)

```python
# Lambda handler with Cognito context
def handler(event, context):
    # Cognito claims available in requestContext
    claims = event['requestContext']['authorizer']['claims']
    user_id = claims['sub']
    email = claims['email']

    return {
        'statusCode': 200,
        'body': json.dumps({'userId': user_id})
    }
```

### JWT Authorization (HTTP API)

```yaml
authorizers:
  jwt:
    authorizer_type: "JWT"
    identity_sources:
      - "$request.header.Authorization"
    jwt_configuration:
      issuer: "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxx"
      audience:
        - "client-id"
```

### API Key Authentication

```bash
# Include API key in request
curl -H "x-api-key: YOUR_API_KEY" https://api.example.com/v1/users
```

## Usage Plans and Throttling

### Tier Configuration

| Tier | Quota | Burst | Rate |
|------|-------|-------|------|
| Free | 1,000/month | 10 | 5/sec |
| Basic | 50,000/month | 100 | 50/sec |
| Premium | 1,000,000/month | 2,000 | 1,000/sec |
| Internal | Unlimited | 5,000 | 2,500/sec |

### Setting Up Usage Plans

```yaml
usage_plans:
  premium:
    name: "premium-tier"
    quota_settings:
      limit: 1000000
      period: "MONTH"
    throttle_settings:
      burst_limit: 2000
      rate_limit: 1000
```

## WAF Protection

### Managed Rules

| Rule Set | Protection |
|----------|------------|
| AWSManagedRulesCommonRuleSet | OWASP Top 10 |
| AWSManagedRulesKnownBadInputsRuleSet | Known malicious patterns |
| AWSManagedRulesSQLiRuleSet | SQL injection |
| AWSManagedRulesBotControlRuleSet | Bot management |

### Custom Rules

```yaml
rules:
  # Rate limiting per IP
  rate-limit:
    name: "RateLimit"
    priority: 40
    action: "BLOCK"
    statement:
      rate_based_statement:
        limit: 2000
        aggregate_key_type: "IP"

  # Geo blocking
  geo-block:
    name: "GeoBlock"
    priority: 50
    action: "BLOCK"
    statement:
      geo_match_statement:
        country_codes:
          - "XX"  # Country codes to block
```

## Cost Estimation

### Monthly Cost Breakdown

| Component | Minimum | Typical | Maximum |
|-----------|---------|---------|---------|
| REST API Gateway | $3.50 | $35 | $350 |
| HTTP API Gateway | $1 | $10 | $100 |
| WebSocket API | $1 | $10 | $100 |
| Lambda | $0 | $20 | $200 |
| WAF | $6 | $15 | $50 |
| Cognito | $0 | $10 | $100 |
| DynamoDB | $1 | $10 | $100 |
| ACM | $0 | $0 | $0 |
| Route53 | $1 | $2 | $10 |
| CloudWatch | $5 | $25 | $100 |
| **TOTAL** | **$18.50** | **$137** | **$1,110** |

### Cost Optimization Tips

1. **Use HTTP APIs**: 70% cheaper than REST APIs for simple use cases
2. **Enable Caching**: Reduce backend invocations
3. **Right-size Lambda**: Optimize memory allocation
4. **Filter at WAF**: Block bad requests before they reach Lambda
5. **Use Compression**: Reduce data transfer costs

## Testing Strategy

### Unit Tests

```bash
# Test Lambda handlers
pytest tests/unit/handlers/ -v
```

### Integration Tests

```bash
# Test API endpoints
atmos workflow test-pattern-integration -f patterns.yaml \
  pattern=api-gateway \
  stack=<tenant>-<environment>
```

### Load Tests

```bash
# Using Artillery
artillery run tests/load/api-load.yml \
  --target https://api.example.com \
  --duration 5m \
  --rate 100
```

### Security Tests

```bash
# Test WAF rules
nikto -h https://api.example.com
sqlmap -u "https://api.example.com/users?id=1" --batch
```

## Monitoring

### CloudWatch Dashboard

The pattern deploys a comprehensive dashboard with:

- Request count and latency
- 4XX and 5XX error rates
- Cache hit/miss ratio (REST API)
- WAF blocked requests
- Lambda invocations and errors
- WebSocket connection metrics

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| 5XXError | Server errors | > 10 in 5 min |
| 4XXError | Client errors | > 100 in 5 min |
| Latency (p99) | Response time | > 3 seconds |
| IntegrationLatency | Backend time | > 2 seconds |
| CacheHitCount | Cache hits | < 50% hit rate |

### Alarms

```yaml
alarms:
  rest-api-5xx-errors:
    metric_name: "5XXError"
    threshold: 10
    period: 300
    evaluation_periods: 2

  rest-api-latency:
    metric_name: "Latency"
    extended_statistic: "p99"
    threshold: 3000
    period: 300
```

## Security Best Practices

### Authentication

1. **Always Use HTTPS**: Enforce TLS 1.2+
2. **Validate Tokens**: Use Cognito or custom authorizers
3. **Rotate API Keys**: Implement key rotation strategy
4. **Scope Permissions**: Use fine-grained IAM policies

### API Security

1. **Request Validation**: Validate all input
2. **Rate Limiting**: Prevent abuse
3. **WAF Protection**: Block known attack patterns
4. **Logging**: Enable access logging for audit

### Data Protection

1. **Encrypt in Transit**: TLS for all connections
2. **Encrypt at Rest**: KMS for stored data
3. **Minimize Data**: Only return necessary fields
4. **Mask Sensitive Data**: In logs and error messages

## Troubleshooting

### Common Issues

#### 401 Unauthorized

1. Check token expiration
2. Verify audience claim
3. Check authorizer configuration
4. Review Cognito user pool settings

#### 403 Forbidden

1. Check WAF rules
2. Verify API key
3. Check usage plan quota
4. Review resource policy

#### 502 Bad Gateway

1. Check Lambda errors
2. Verify Lambda timeout
3. Check VPC Link connectivity
4. Review integration response

#### High Latency

1. Enable caching (REST API)
2. Optimize Lambda cold starts
3. Check VPC configuration
4. Review database queries

### Debugging Commands

```bash
# Check API Gateway logs
aws logs filter-log-events \
  --log-group-name "/aws/apigateway/${api_name}" \
  --filter-pattern "ERROR"

# Check Lambda errors
aws logs filter-log-events \
  --log-group-name "/aws/lambda/${function_name}" \
  --filter-pattern "ERROR"

# Check WAF blocked requests
aws wafv2 get-sampled-requests \
  --web-acl-arn ${web_acl_arn} \
  --rule-metric-name "ALL" \
  --scope REGIONAL \
  --time-window StartTime=2024-01-01T00:00:00Z,EndTime=2024-01-02T00:00:00Z \
  --max-items 100

# Test API endpoint
curl -v -H "Authorization: Bearer ${token}" \
  -H "x-api-key: ${api_key}" \
  https://api.example.com/v1/users
```

## Best Practices

### API Design

1. **Use Semantic Versioning**: /v1, /v2
2. **Consistent Naming**: Use nouns for resources
3. **Proper HTTP Methods**: GET, POST, PUT, DELETE
4. **Meaningful Status Codes**: 200, 201, 400, 401, 404, 500
5. **HATEOAS**: Include links in responses

### Performance

1. **Enable Caching**: For frequently accessed data
2. **Compress Responses**: Enable gzip
3. **Pagination**: Limit response sizes
4. **Async Operations**: Use callbacks for long operations

### Documentation

1. **OpenAPI Spec**: Maintain up-to-date documentation
2. **Developer Portal**: Provide self-service access
3. **Change Log**: Document API changes
4. **Examples**: Include request/response examples

## Related Patterns

- [Event-Driven Architecture](./EVENT_DRIVEN_ARCHITECTURE.md): Async event processing
- [Streaming Pipeline](./STREAMING_PIPELINES.md): Real-time data processing
- [Serverless API Stack](../library/templates/serverless-api-stack.md): Complete serverless API

## References

- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/latest/developerguide/)
- [API Gateway Best Practices](https://docs.aws.amazon.com/apigateway/latest/developerguide/best-practices.html)
