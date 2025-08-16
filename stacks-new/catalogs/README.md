# Component Catalogs

This directory contains component catalogs that define standardized configurations for Terraform components across different environments and use cases.

## Structure

```
catalogs/
├── foundation/          # Foundation components (networking, security)
├── platform/           # Platform services (EKS, databases)  
├── application/        # Application-level components
└── observability/      # Monitoring and observability components
```

## Purpose

Component catalogs provide:

1. **Standardized Configurations** - Pre-configured components with sensible defaults
2. **Environment-Specific Variations** - Different configurations for dev/staging/production
3. **Compliance Alignment** - Components configured to meet compliance requirements
4. **Best Practices** - Components that follow security and operational best practices

## Usage

Component catalogs are imported into stack configurations and can be customized per environment. The catalog provides the base configuration, while stack-specific overrides handle environment differences.

Example:
```yaml
# In a stack configuration
imports:
  - "catalogs/foundation/vpc"
  - "catalogs/platform/eks"
  
components:
  terraform:
    vpc:
      # Inherits from catalog with environment-specific overrides
      vars:
        cidr_block: "10.0.0.0/16"  # Override catalog default
```

## Component Categories

### Foundation Components
- **VPC** - Virtual Private Cloud with subnets, route tables, gateways
- **Security Groups** - Network-level access controls
- **IAM** - Identity and access management roles and policies
- **KMS** - Key management for encryption
- **S3** - Object storage with lifecycle policies
- **Route53** - DNS management
- **Certificate Manager** - SSL/TLS certificate management

### Platform Components
- **EKS** - Kubernetes cluster with managed node groups
- **RDS** - Relational database instances with backup/monitoring
- **ElastiCache** - In-memory caching
- **Lambda** - Serverless compute functions
- **API Gateway** - REST API management
- **Load Balancers** - Application and network load balancing
- **Auto Scaling** - Dynamic scaling configurations

### Application Components
- **ECR** - Container registry
- **ECS** - Container orchestration
- **CodePipeline** - CI/CD pipelines
- **CodeBuild** - Build automation
- **SecretsManager** - Application secrets management
- **Parameter Store** - Configuration management

### Observability Components
- **CloudWatch** - Monitoring and alerting
- **X-Ray** - Distributed tracing
- **Config** - Configuration monitoring
- **GuardDuty** - Threat detection
- **Security Hub** - Security posture monitoring
- **CloudTrail** - API auditing

## Component Configuration Pattern

Each component catalog follows a consistent pattern:

```yaml
# Component metadata
metadata:
  name: "component-name"
  description: "Component description"
  version: "1.0.0"
  
# Environment-specific configurations  
configurations:
  production:
    # Production-optimized settings
    
  staging: 
    # Staging-specific settings
    
  development:
    # Development-optimized settings
    
# Common variables across all environments
vars:
  # Common settings
  
# Component-specific tags
tags:
  ComponentType: "Platform"
  ServiceLevel: "Foundation"
```

## Best Practices

1. **Version Control** - All component catalogs are versioned
2. **Documentation** - Each component includes comprehensive documentation
3. **Testing** - Components include test configurations
4. **Security** - All components follow security best practices
5. **Compliance** - Components support required compliance frameworks
6. **Monitoring** - Components include observability configurations
7. **Cost Optimization** - Components are optimized for cost efficiency