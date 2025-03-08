# QA Environment Template

This template provides a standardized configuration for Quality Assurance (QA) environments.

## Purpose

QA environments are designed for:
- Testing and validation of features before production
- Load and performance testing
- Integration testing with external systems
- Automated test execution

## Features

- **VPC Configuration**:
  - Production-like VPC with public and private subnets
  - Single or multiple NAT gateways based on availability requirements
  - VPC flow logs with 30-day retention for troubleshooting

- **Compute Resources**:
  - Right-sized instances for QA workloads
  - Autoscaling with moderate minimums
  - On-demand instances with cost optimization

- **Security**:
  - Security groups mirroring production
  - Test-appropriate IAM policies
  - Medium retention periods for logs (30 days)
  - Simplified security tooling

- **Monitoring**:
  - QA-specific CloudWatch dashboards
  - Critical and warning alerts
  - Standard log collection
  - Test automation integration

## Usage

To create a new QA environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=qa \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=qa \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | t3.large | EKS node instance type |
| eks_node_min_count | 2 | Minimum number of EKS nodes |
| eks_node_max_count | 6 | Maximum number of EKS nodes |
| retention_days | 30 | Log retention period in days |
| detailed_monitoring | true | Whether to enable detailed CloudWatch monitoring |
| vpc_flow_logs_enabled | true | Whether to enable VPC flow logs |
| endpoint_private_access | true | Whether EKS endpoint has private access |
| endpoint_public_access | true | Whether EKS endpoint has public access |

## Testing Integrations

This template includes:
- Automated test execution frameworks
- Test data generation utilities
- Performance testing tools configuration
- Test report generation