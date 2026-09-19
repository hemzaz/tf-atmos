# Multiple Component Instances - testenv-01 Environment

This directory contains a consolidated implementation of the Atmos Multiple Component Instances design pattern for the testenv-01 environment. The structure organizes components by functional domain while leveraging multiple instances of the same Terraform components.

## File Structure

| File | Description | Purpose |
|------|-------------|---------|
| `globals.yaml` | Environment globals | Defines environment-wide variables, imports, and tags |
| `networking.yaml` | Network resources | VPC instances and their DNS (`network/*`) instances |
| `security.yaml` | Security resources | IAM, ACM, Secrets Manager, backend component instances |
| `compute.yaml` | Compute resources | EKS, EC2, and external-secrets component instances |
| `services.yaml` | Service resources | API Gateway, monitoring, and infrastructure component instances |

## Component Instances Overview

### VPC/Network Components
- **vpc/main**: Primary VPC for general workloads (10.0.0.0/16)
- **vpc/services**: Secondary VPC for data services (10.1.0.0/16)
- **network/main**: Route 53 zones for the main VPC (`dns` root module)
- **network/services**: Route 53 zones for the services VPC (`dns` root module)

### Security Components
- **iam/dev**: Development IAM roles and policies 
- **iam/ci**: CI/CD IAM roles (disabled: the `iam` module only manages a cross-account role)
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
- **infrastructure/main**: Main infrastructure resources (ECS, RDS); disabled, no `infrastructure` root module yet
- **infrastructure/data**: Data infrastructure resources; disabled, same reason
- **monitoring/main**: Main monitoring configuration
- **monitoring/data**: Data monitoring configuration

## Usage

Deploy component groups (layers of `workflows/deploy-full-stack.yaml`, selected by root module):

```bash
# Deploy all networking components
atmos workflow deploy-networking -f deploy-full-stack -s fnx-dev-testenv-01

# Deploy all security components
atmos workflow deploy-security -f deploy-full-stack -s fnx-dev-testenv-01

# Deploy specific component instances
atmos terraform deploy vpc/main -s fnx-dev-testenv-01
atmos terraform deploy eks/data -s fnx-dev-testenv-01
```

## Dependencies

Instances declare their order with `dependencies.components` (for example `eks/main` depends on
`vpc/main`), and cross-component values are read with `!terraform.state`, so an instance can only
be planned after the instances it reads from are deployed. `atmos workflow deploy -f
deploy-full-stack -s fnx-dev-testenv-01` runs the layers in order: foundation, networking,
security, compute, platform, data, services, monitoring.
