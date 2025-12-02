# Alexandria Library - Terraform Module Collection

Welcome to the Alexandria Library - a comprehensive collection of 50+ production-ready, reusable Terraform modules for AWS infrastructure.

## Module Categories

### 1. Networking (10 modules)

| Module | Status | Description |
|--------|--------|-------------|
| [vpc-advanced](./networking/vpc-advanced/) | ✅ Complete | Full-featured VPC with all options |
| vpc-peering | 🚧 Planned | VPC peering with route propagation |
| transit-gateway | 🚧 Planned | Multi-VPC connectivity |
| vpc-endpoints | 🚧 Planned | Service endpoints management |
| network-firewall | 🚧 Planned | AWS Network Firewall |
| security-baseline | 🚧 Planned | Account security baseline |
| security-groups-factory | 🚧 Planned | Dynamic security group generation |
| waf-rulesets | 🚧 Planned | WAF rule collections |
| shield-advanced | 🚧 Planned | DDoS protection |
| iam-identity-center | 🚧 Planned | AWS IAM Identity Center setup |

### 2. Compute (10 modules)

| Module | Status | Description |
|--------|--------|-------------|
| eks-blueprint | ✅ Complete | Production EKS with all addons |
| lambda-function | ✅ Complete | Lambda with all features |
| ecs-fargate-service | 🚧 Planned | Fargate service template |
| ecs-ec2-cluster | 🚧 Planned | EC2-based ECS cluster |
| eks-node-groups | 🚧 Planned | Managed/self-managed node groups |
| lambda-layer | 🚧 Planned | Reusable Lambda layers |
| step-functions | 🚧 Planned | State machine workflows |
| ec2-autoscaling | 🚧 Planned | Auto-scaling groups |
| ec2-spot-fleet | 🚧 Planned | Cost-optimized compute |
| ec2-placement-groups | 🚧 Planned | High-performance computing |

### 3. Data Layer (12 modules)

| Module | Status | Description |
|--------|--------|-------------|
| rds-postgres | ✅ Complete | PostgreSQL with best practices |
| s3-bucket | ✅ Complete | S3 with all features |
| dynamodb-table | ✅ Complete | DynamoDB with all features |
| rds-aurora | 🚧 Planned | Aurora cluster with all features |
| rds-mysql | 🚧 Planned | MySQL with best practices |
| documentdb | 🚧 Planned | DocumentDB cluster |
| elasticache-redis | 🚧 Planned | Redis cluster |
| elasticache-memcached | 🚧 Planned | Memcached cluster |
| dax | 🚧 Planned | DynamoDB Accelerator |
| efs-filesystem | 🚧 Planned | EFS with mount targets |
| fsx-lustre | 🚧 Planned | FSx for Lustre |
| fsx-windows | 🚧 Planned | FSx for Windows |

### 4. Integration (8 modules)

| Module | Status | Description |
|--------|--------|-------------|
| sqs-queue | ✅ Complete | SQS with DLQ |
| sns-topic | 🚧 Planned | SNS with subscriptions |
| mq-broker | 🚧 Planned | Amazon MQ |
| api-gateway-rest | 🚧 Planned | REST API with auth |
| api-gateway-http | 🚧 Planned | HTTP API |
| appsync-api | 🚧 Planned | GraphQL API |
| kinesis-stream | 🚧 Planned | Kinesis data stream |
| kafka-cluster | 🚧 Planned | MSK cluster |

### 5. Observability (6 modules)

| Module | Status | Description |
|--------|--------|-------------|
| cloudwatch-logs | 🚧 Planned | Log group with filters |
| cloudwatch-dashboard | 🚧 Planned | Dashboard builder |
| cloudwatch-alarms | 🚧 Planned | Alarm factory |
| elasticsearch-domain | 🚧 Planned | OpenSearch for logs |
| xray-sampling | 🚧 Planned | X-Ray configuration |
| grafana-workspace | 🚧 Planned | Managed Grafana |

### 6. Security (8 modules)

| Module | Status | Description |
|--------|--------|-------------|
| secrets-manager | ✅ Complete | Secret with rotation |
| kms-key | ✅ Complete | KMS key with policies |
| cognito-user-pool | 🚧 Planned | User authentication |
| cognito-identity-pool | 🚧 Planned | Federated identities |
| parameter-store | 🚧 Planned | SSM parameters |
| config-rules | 🚧 Planned | AWS Config compliance |
| security-hub-standards | 🚧 Planned | Security Hub config |
| audit-logging | 🚧 Planned | CloudTrail with S3 |

### 7. Application Patterns (6 modules)

| Module | Status | Description |
|--------|--------|-------------|
| three-tier-web-app | 🚧 Planned | Classic 3-tier architecture |
| microservices-platform | 🚧 Planned | EKS-based microservices |
| serverless-api | 🚧 Planned | API Gateway + Lambda + DynamoDB |
| data-lake | 🚧 Planned | S3 + Glue + Athena |
| streaming-pipeline | 🚧 Planned | Kinesis + Lambda + S3 |
| batch-processing | 🚧 Planned | Batch + ECS |

## Module Standards

All modules in the Alexandria Library follow these standards:

### File Structure
```
module-name/
├── README.md           # Comprehensive documentation
├── main.tf            # Primary resource definitions
├── variables.tf       # Input variables with validation
├── outputs.tf         # Output values with descriptions
├── versions.tf        # Terraform and provider versions
├── CHANGELOG.md       # Version history
├── examples/
│   ├── complete/      # Full-featured example
│   └── simple/        # Basic example
└── tests/             # Terratest or similar
```

### Code Standards
- Use snake_case for resources, variables, outputs
- Include detailed variable descriptions with validation
- Mark sensitive outputs with `sensitive = true`
- Apply consistent tags to all resources
- Follow naming: `${local.name_prefix}-<resource-type>`

### Documentation Standards
- Complete README with usage examples
- At least 2 working examples
- Input/output tables
- Requirements and providers
- Known issues
- Best practices
- Cost estimation

### Security Standards
- Encrypt sensitive data at rest and in transit
- Use least privilege IAM policies
- Store secrets in SSM/Secrets Manager
- Never commit sensitive information
- Use specific CIDR blocks, avoid 0.0.0.0/0

## Usage

### Using a Module

```hcl
module "example" {
  source = "../../_library/category/module-name"

  name_prefix = "myapp"
  environment = "production"

  # Module-specific variables
  ...

  tags = {
    Terraform = "true"
    Owner     = "platform-team"
  }
}
```

### Module Versioning

Modules follow [Semantic Versioning](https://semver.org/):
- MAJOR version for incompatible API changes
- MINOR version for backwards-compatible functionality additions
- PATCH version for backwards-compatible bug fixes

## Testing

All modules should include:
- Input validation tests
- Resource creation tests
- Output verification tests
- Integration tests (where applicable)

## Contributing

When adding new modules:
1. Follow the module standards above
2. Include comprehensive documentation
3. Add at least 2 working examples
4. Include CHANGELOG.md
5. Test thoroughly before committing

## Support

For issues or questions:
- Check module README for known issues
- Review examples for usage patterns
- Consult AWS documentation for service-specific details

## License

This module collection is part of the tf-atmos project.

---

**Note**: Modules marked with ✅ are complete and production-ready. Modules marked with 🚧 are planned for future releases.
