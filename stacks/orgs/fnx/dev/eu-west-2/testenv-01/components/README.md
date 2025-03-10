# Multiple Component Instances - testenv-01 Environment

This directory contains a consolidated implementation of the Atmos Multiple Component Instances design pattern for the testenv-01 environment. The structure organizes components by functional domain while leveraging multiple instances of the same Terraform components.

## File Structure

| File | Description | Purpose |
|------|-------------|---------|
| `globals.yaml` | Environment globals | Defines environment-wide variables, imports, and tags |
| `networking.yaml` | Network resources | Multiple VPC and network component instances |
| `security.yaml` | Security resources | IAM, ACM, Secrets Manager, backend component instances |
| `compute.yaml` | Compute resources | EKS, EC2, and external-secrets component instances |
| `services.yaml` | Service resources | API Gateway, monitoring, and infrastructure component instances |

## Component Instances Overview

### VPC/Network Components
- **vpc/main**: Primary VPC for general workloads (10.0.0.0/16)
- **vpc/services**: Secondary VPC for data services (10.1.0.0/16)
- **network/main**: DNS and network settings for main VPC
- **network/services**: DNS and network settings for services VPC

### Security Components
- **iam/dev**: Development IAM roles and policies 
- **iam/ci**: CI/CD specific IAM roles
- **acm/main**: Main wildcard certificate
- **acm/services**: Services subdomain certificate
- **secretsmanager/app**: Application secrets
- **secretsmanager/infra**: Infrastructure secrets
- **backend/main**: Terraform backend resources

### Compute Components
- **eks/main**: Main application Kubernetes cluster
- **eks/data**: Data processing Kubernetes cluster
- **ec2/bastion**: Bastion host for SSH access
- **ec2/app-server**: Application server
- **external-secrets/main**: Secrets for main cluster
- **external-secrets/data**: Secrets for data cluster

### Service Components
- **apigateway/main**: Main API Gateway
- **apigateway/data**: Data API Gateway
- **infrastructure/main**: Main infrastructure resources (ECS, RDS)
- **infrastructure/data**: Data infrastructure resources
- **monitoring/main**: Main monitoring configuration
- **monitoring/data**: Data monitoring configuration

## Usage

Deploy component groups:

```bash
# Deploy all networking components
atmos terraform apply -c networking.yaml -s fnx-dev-eu-west-2-testenv-01

# Deploy all security components
atmos terraform apply -c security.yaml -s fnx-dev-eu-west-2-testenv-01

# Deploy specific component instances
atmos terraform apply vpc/main -s fnx-dev-eu-west-2-testenv-01
atmos terraform apply eks/data -s fnx-dev-eu-west-2-testenv-01
```

## Dependencies

Components should be deployed in this order:
1. networking.yaml - Foundation infrastructure
2. security.yaml - Security and IAM configuration 
3. compute.yaml - EKS clusters and compute resources
4. services.yaml - Applications and monitoring