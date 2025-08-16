# Deployment Configurations

This directory contains the actual deployment stack configurations that combine mixins, catalogs, and environment-specific settings to create deployable infrastructure stacks.

## Structure

```
deployments/
├── fnx/                    # Tenant-specific deployments
│   ├── dev/               # Development account
│   │   ├── us-west-2/     # Primary region
│   │   │   ├── testenv-01/  # Test environment
│   │   │   └── development/ # Development environment
│   │   └── us-east-1/     # DR region
│   ├── staging/           # Staging account  
│   │   └── us-west-2/
│   │       └── staging/
│   └── prod/              # Production account
│       ├── us-west-2/     # Primary region
│       │   └── production/
│       └── us-east-1/     # DR region
│           └── production/
└── shared/                # Shared/common deployments
    └── security/          # Shared security account
```

## Stack Naming Convention

Stacks follow the pattern: `{tenant}-{account}-{region}-{environment}`

Examples:
- `fnx-dev-us-west-2-testenv-01`
- `fnx-staging-us-west-2-staging`
- `fnx-prod-us-west-2-production`
- `fnx-prod-us-east-1-production`

## Stack Configuration Pattern

Each deployment stack combines:

1. **Global Settings** - Universal configuration from `_globals/`
2. **Mixins** - Account, region, environment, and compliance mixins
3. **Component Catalogs** - Standardized component configurations
4. **Stack-Specific Overrides** - Environment-specific customizations

Example stack structure:
```yaml
# Stack imports (order matters)
imports:
  # Global settings
  - "_globals/globals"
  
  # Mixins (in dependency order)
  - "mixins/accounts/development"
  - "mixins/regions/us-west-2"  
  - "mixins/environments/testenv-01"
  
  # Component catalogs
  - "catalogs/foundation/vpc"
  - "catalogs/platform/eks"
  
# Stack-specific variables
vars:
  tenant: "fnx"
  account: "dev"
  region: "us-west-2"
  environment: "testenv-01"
  
  # Stack-specific overrides
  vpc_cidr: "10.2.0.0/16"
  
# Component configurations
components:
  terraform:
    vpc:
      vars:
        cidr_block: ${vpc_cidr}
        
    eks:
      vars:
        cluster_name: "${tenant}-${environment}-eks"
```

## Deployment Process

1. **Plan** - `atmos terraform plan {component} -s {stack}`
2. **Apply** - `atmos terraform apply {component} -s {stack}`
3. **Validate** - `atmos terraform validate {component} -s {stack}`

For full environment deployment:
```bash
atmos workflow apply-environment tenant=fnx account=dev environment=testenv-01
```

## Environment Progression

Infrastructure typically follows this deployment progression:

1. **Development** - `fnx-dev-us-west-2-development`
   - Cost-optimized, flexible configuration
   - Spot instances, single AZ where possible
   - Relaxed security for developer productivity

2. **Test Environment** - `fnx-dev-us-west-2-testenv-01`  
   - Production-like configuration for testing
   - Multi-AZ for high availability testing
   - Performance monitoring enabled

3. **Staging** - `fnx-staging-us-west-2-staging`
   - Production-parity configuration
   - Full security and compliance enabled
   - User acceptance testing environment

4. **Production** - `fnx-prod-us-west-2-production`
   - High availability, security-first
   - Full compliance frameworks
   - Enhanced monitoring and alerting

5. **Disaster Recovery** - `fnx-prod-us-east-1-production`
   - Cross-region replication target
   - Automated backup storage
   - Standby infrastructure for failover

## Dependencies

Stack deployments have dependencies that must be deployed in order:

### Foundation Layer
1. **KMS** - Encryption keys
2. **IAM** - Roles and policies  
3. **VPC** - Network foundation
4. **Security Groups** - Network security

### Platform Layer  
5. **RDS** - Databases (requires VPC, security groups)
6. **EKS** - Kubernetes (requires VPC, IAM)
7. **Load Balancers** - Traffic routing
8. **Certificate Manager** - SSL/TLS certificates

### Application Layer
9. **Lambda** - Serverless functions
10. **API Gateway** - API management
11. **ECR** - Container registry
12. **Application components**

### Observability Layer
13. **CloudWatch** - Monitoring
14. **X-Ray** - Tracing  
15. **Config** - Configuration monitoring

## Best Practices

1. **Incremental Deployment** - Deploy components in dependency order
2. **Environment Parity** - Keep staging/production configurations similar
3. **Testing** - Validate in lower environments before production
4. **Rollback Planning** - Plan for rollback scenarios
5. **State Management** - Use remote state with locking
6. **Security** - Follow least privilege principles
7. **Monitoring** - Monitor deployments and infrastructure health
8. **Documentation** - Document environment-specific configurations