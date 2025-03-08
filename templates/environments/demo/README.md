# Demo Environment Template

This template provides a standardized configuration for Demo environments.

## Purpose

Demo environments are designed for:
- Customer demonstrations and proof-of-concepts
- Sales presentations and training
- Showcasing features in a controlled environment
- Short to medium-term usage with easy teardown

## Features

- **VPC Configuration**:
  - Simplified VPC with public and private subnets
  - Single NAT gateway for cost optimization
  - Basic networking with demonstration-friendly IPs

- **Compute Resources**:
  - Right-sized instances for demo workloads
  - Fixed capacity (limited or no autoscaling)
  - Preloaded with demonstration data
  - Scheduled start/stop for cost savings

- **Security**:
  - Demo-appropriate security groups
  - Simplified IAM policies
  - Short retention periods for logs (7 days)
  - Sanitized data with no PII

- **Monitoring**:
  - Demonstration-focused dashboards
  - Limited alerting
  - Demo metrics for presentations

## Usage

To create a new demo environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=demo \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=demo \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | t3.medium | EKS node instance type |
| eks_node_count | 2 | Fixed number of EKS nodes |
| retention_days | 7 | Log retention period in days |
| detailed_monitoring | false | Whether to enable detailed CloudWatch monitoring |
| preload_demo_data | true | Whether to preload demonstration data |
| schedule_shutdown | true | Whether to enable scheduled shutdown during non-business hours |

## Demo Features

This template includes:
- Sample application deployments
- Demonstration data sets
- Showcase dashboards
- Simplified authentication for demos
- One-click reset capability