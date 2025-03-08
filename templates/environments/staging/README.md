# Staging Environment Template

This template provides a standardized configuration for Staging environments.

## Purpose

Staging environments are designed for:
- Final validation before production deployment
- Production-like configuration with cost optimizations
- Pre-release testing with real data (sanitized)
- Feature verification in a production-similar setting

## Features

- **VPC Configuration**:
  - Production-similar VPC with public and private subnets
  - Redundant NAT gateways for availability
  - VPC flow logs with 30-day retention
  - Similar networking rules to production

- **Compute Resources**:
  - Similar instance types to production but fewer resources
  - Appropriate autoscaling for staging workloads
  - Mix of on-demand and spot instances for cost optimization

- **Security**:
  - Security groups mirroring production
  - Moderately strict IAM policies
  - Medium retention periods for logs (30 days)
  - Most security services enabled (similar to production)

- **Monitoring**:
  - Comprehensive CloudWatch dashboards
  - Same alert patterns as production
  - Full metrics collection
  - Integration with monitoring tools

## Usage

To create a new staging environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=staging \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=staging \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | m5.large | EKS node instance type |
| eks_node_min_count | 2 | Minimum number of EKS nodes |
| eks_node_max_count | 6 | Maximum number of EKS nodes |
| retention_days | 30 | Log retention period in days |
| detailed_monitoring | true | Whether to enable detailed CloudWatch monitoring |
| vpc_flow_logs_enabled | true | Whether to enable VPC flow logs |
| endpoint_private_access | true | Whether EKS endpoint has private access |
| endpoint_public_access | true | Whether EKS endpoint has public access |
| public_access_cidrs | ["10.0.0.0/8"] | CIDR blocks allowed public access |

## Staging Best Practices

- Use feature flags to enable/disable new features
- Deploy with the same pipeline as production
- Run performance tests in this environment
- Maintain data similarity to production with sanitized data
- Test rollback procedures in staging
- Use the same tooling as production