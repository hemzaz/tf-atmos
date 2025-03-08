# Production Environment Template

This template provides a standardized configuration for Production environments.

## Purpose

Production environments are designed for:
- Running customer-facing workloads
- Maximum reliability and availability
- Strict security configurations
- Comprehensive monitoring and observability

## Features

- **VPC Configuration**:
  - Highly available VPC with public and private subnets across multiple AZs
  - Multiple NAT gateways for high availability
  - VPC flow logs with 90-day retention for audit purposes
  - Network ACLs for additional security

- **Compute Resources**:
  - Right-sized instances with production performance characteristics
  - Autoscaling with appropriate minimums for availability
  - Reserved instances recommended

- **Security**:
  - Restrictive security groups
  - Least-privilege IAM policies
  - Long retention periods for logs (90+ days)
  - GuardDuty, Security Hub, and Config enabled
  - KMS encryption for all sensitive data

- **Monitoring**:
  - Comprehensive CloudWatch dashboards
  - Critical and warning alerts
  - Detailed metrics collection
  - Centralized logging with advanced search capabilities

## Usage

To create a new production environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=prod \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=production \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | m5.large | EKS node instance type |
| eks_node_min_count | 3 | Minimum number of EKS nodes |
| eks_node_max_count | 10 | Maximum number of EKS nodes |
| retention_days | 90 | Log retention period in days |
| detailed_monitoring | true | Whether to enable detailed CloudWatch monitoring |
| vpc_flow_logs_enabled | true | Whether to enable VPC flow logs |
| endpoint_private_access | true | Whether EKS endpoint has private access |
| endpoint_public_access | false | Whether EKS endpoint has public access |

## Compliance Integrations

This template supports multiple compliance frameworks:
- SOC 2
- HIPAA
- PCI-DSS
- ISO 27001

Configure the compliance level through the `compliance_level` parameter.