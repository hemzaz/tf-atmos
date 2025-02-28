# Component Catalog

This document provides a comprehensive overview of all available infrastructure components in the Atmos framework.

## Network Layer

| Component | Description | Features |
|-----------|-------------|----------|
| [vpc](../components/terraform/vpc) | Virtual Private Cloud infrastructure | Multi-AZ, public/private subnets, NAT gateways, VPN connectivity |
| [dns](../components/terraform/dns) | Route53 DNS management | Public/private hosted zones, record management |
| [securitygroup](../components/terraform/securitygroup) | Security group management | Predefined rule sets, dynamic rule generation |

## Compute Layer

| Component | Description | Features |
|-----------|-------------|----------|
| [ec2](../components/terraform/ec2) | EC2 instance management | Auto-scaling groups, launch templates, instance profiles |
| [ecs](../components/terraform/ecs) | Elastic Container Service | Fargate/EC2 clusters, task definitions, services |
| [eks](../components/terraform/eks) | Elastic Kubernetes Service | Managed node groups, Fargate profiles, IRSA |
| [eks-addons](../components/terraform/eks-addons) | EKS add-on management | Ingress controllers, autoscalers, monitoring tools |
| [lambda](../components/terraform/lambda) | Serverless functions | Event triggers, resource permissions, monitoring |

## Data Layer

| Component | Description | Features |
|-----------|-------------|----------|
| [rds](../components/terraform/rds) | Relational Database Service | Multi-AZ, read replicas, automated backups |
| [backend](../components/terraform/backend) | Terraform state management | S3 buckets, DynamoDB locking tables |

## Security Layer

| Component | Description | Features |
|-----------|-------------|----------|
| [iam](../components/terraform/iam) | Identity and Access Management | Cross-account roles, custom policies |
| [secretsmanager](../components/terraform/secretsmanager) | AWS Secrets Manager | Hierarchical secrets, automatic rotation |
| [acm](../components/terraform/acm) | Certificate Management | Public/private certificates, automatic validation |
| [external-secrets](../components/terraform/external-secrets) | External Secrets Operator | Kubernetes integration for secrets |

## API Layer

| Component | Description | Features |
|-----------|-------------|----------|
| [apigateway](../components/terraform/apigateway) | API Gateway | REST/HTTP APIs, custom domains, authentication |
| [monitoring](../components/terraform/monitoring) | CloudWatch dashboards and alarms | Custom metrics, alerting, log aggregation |

## Integration Patterns

Common integration patterns between components:

### Web Application Pattern

```
VPC → Security Groups → ECS/EKS → API Gateway → ACM → Route53
```

### Data Processing Pattern

```
VPC → Security Groups → Lambda → RDS → Secrets Manager
```

### Kubernetes Application Pattern

```
VPC → EKS → EKS-Addons → External-Secrets → Secrets Manager
```

## Component Development Status

| Status | Description | Components |
|--------|-------------|------------|
| ✅ Stable | Production-ready | vpc, dns, ec2, rds, iam, backend, secretsmanager, acm |
| 🔄 Beta | Feature complete but evolving | eks, eks-addons, apigateway, monitoring, external-secrets |
| 🚧 Alpha | Under active development | lambda, ecs |

## Adding Custom Components

See the [Component Creation Guide](component-creation-guide.md) for instructions on developing your own components.