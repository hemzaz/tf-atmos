# Development Environment Template

This template provides a standardized configuration for Development environments.

## Purpose

Development environments are designed for:
- Rapid iteration and testing
- Lower infrastructure costs
- Relaxed security configurations compared to production
- Individual developer or team usage

## Features

- **VPC Configuration**:
  - Simple VPC with public and private subnets
  - Single NAT gateway for cost optimization
  - Basic flow logs for troubleshooting

- **Compute Resources**:
  - Small/medium sized instances
  - Autoscaling with lower minimums
  - Spot instances where appropriate

- **Security**:
  - Basic security groups
  - Development-appropriate IAM policies
  - Lower retention periods for logs (14 days)

- **Monitoring**:
  - Basic CloudWatch dashboards
  - Critical alerts only
  - Standard log collection

## Usage

To create a new development environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=dev \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=development \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | t3.medium | EKS node instance type |
| eks_node_min_count | 2 | Minimum number of EKS nodes |
| eks_node_max_count | 4 | Maximum number of EKS nodes |
| retention_days | 14 | Log retention period in days |
| detailed_monitoring | false | Whether to enable detailed CloudWatch monitoring |

## Recommended Extensions

- Developer namespace configurations for Kubernetes
- CI/CD integration for developer branches
- Local development tools configurations