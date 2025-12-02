# Three-Tier Web Application Blueprint

Production-ready three-tier web application infrastructure on AWS.

## Architecture

```
                    ┌─────────────────┐
                    │   CloudFront    │
                    │      (CDN)      │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │       ALB       │
                    │ (Load Balancer) │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────┴────┐        ┌────┴────┐        ┌────┴────┐
    │   AZ-a  │        │   AZ-b  │        │   AZ-c  │
    │   EKS   │        │   EKS   │        │   EKS   │
    │  Nodes  │        │  Nodes  │        │  Nodes  │
    └────┬────┘        └────┬────┘        └────┬────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                    ┌────────┴────────┐
                    │    RDS Aurora   │
                    │   (Multi-AZ)    │
                    └─────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| VPC | Network foundation with public/private subnets |
| Security Groups | Network security rules |
| EKS | Kubernetes cluster for application |
| EKS Addons | Load balancer controller, autoscaler |
| RDS | PostgreSQL database with Multi-AZ |
| ACM | SSL/TLS certificates |
| Monitoring | CloudWatch dashboards and alarms |

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.5.0
- Atmos >= 1.50.0
- kubectl configured

## Quick Start

1. **Generate Stack**:
```bash
./scripts/library/generate-stack.sh web-app-stack <tenant> <environment>
```

2. **Review Configuration**:
```bash
cat stacks/orgs/<tenant>/<environment>/generated/web-app-stack-generated.yaml
```

3. **Deploy**:
```bash
# Deploy in order
atmos terraform apply vpc -s <tenant>-<environment>
atmos terraform apply securitygroup -s <tenant>-<environment>
atmos terraform apply eks -s <tenant>-<environment>
atmos terraform apply rds -s <tenant>-<environment>
atmos terraform apply monitoring -s <tenant>-<environment>
```

## Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | $300-500 |
| Staging | $500-800 |
| Production | $1,500-3,000+ |

## Customization

### High Availability

Set `nat_gateway_strategy: "one_per_az"` for NAT Gateway HA.

### Database Sizing

Adjust RDS instance class based on workload:
- Development: `db.t3.micro`
- Staging: `db.t3.medium`
- Production: `db.r5.large+`

### Node Group Scaling

Configure EKS node groups:
```yaml
node_groups:
  general:
    min_size: 2
    max_size: 20
```

## Security Features

- Private subnets for application and database
- NAT Gateway for outbound internet access
- Security groups with least privilege
- RDS encryption at rest
- TLS for all traffic
- VPC Flow Logs enabled
