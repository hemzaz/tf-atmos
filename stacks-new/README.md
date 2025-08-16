# Atmos Stacks - Redesigned Architecture

This directory contains the restructured infrastructure stack configurations using a modern, scalable Atmos architecture.

## 🏗️ New Stack Architecture

The redesigned structure follows enterprise best practices with clear separation of concerns:

```
stacks/
├── _globals/                           # Global configurations
│   ├── globals.yaml                    # Universal settings
│   ├── settings/                       # Global settings by category
│   │   ├── security.yaml              # Global security defaults
│   │   ├── networking.yaml            # Global network settings
│   │   ├── compliance.yaml            # Compliance requirements
│   │   └── tags.yaml                  # Standard tagging strategy
│   └── schemas/                        # Validation schemas
│       ├── component-schemas/          # Per-component validation
│       └── stack-schemas/              # Stack validation rules
├── mixins/                            # Reusable configuration mixins
│   ├── accounts/                      # Account-type configurations
│   │   ├── production.yaml           # Production account settings
│   │   ├── staging.yaml              # Staging account settings
│   │   ├── development.yaml          # Development account settings
│   │   └── sandbox.yaml              # Sandbox account settings
│   ├── regions/                       # Region-specific configurations
│   │   ├── us-east-1.yaml            # N. Virginia
│   │   ├── us-east-2.yaml            # Ohio
│   │   ├── us-west-1.yaml            # N. California  
│   │   ├── us-west-2.yaml            # Oregon
│   │   ├── eu-west-1.yaml            # Ireland
│   │   ├── eu-west-2.yaml            # London
│   │   └── eu-central-1.yaml         # Frankfurt
│   ├── environments/                  # Environment-type configurations
│   │   ├── core.yaml                 # Core infrastructure
│   │   ├── platform.yaml             # Platform services
│   │   ├── application.yaml          # Application workloads
│   │   └── data.yaml                 # Data services
│   ├── compliance/                    # Compliance framework mixins
│   │   ├── soc2.yaml                 # SOC2 requirements
│   │   ├── pci-dss.yaml              # PCI-DSS requirements
│   │   ├── hipaa.yaml                # HIPAA requirements
│   │   └── iso27001.yaml             # ISO27001 requirements
│   └── tenants/                       # Tenant-specific configurations
│       ├── fnx.yaml                   # FNX tenant defaults
│       ├── acme.yaml                  # ACME tenant defaults
│       └── core.yaml                  # Core tenant defaults
├── catalogs/                          # Component catalog configurations
│   ├── infrastructure/                # Infrastructure components
│   │   ├── networking/
│   │   │   ├── vpc/
│   │   │   │   ├── defaults.yaml     # VPC default configuration
│   │   │   │   ├── production.yaml   # Production VPC config
│   │   │   │   ├── development.yaml  # Development VPC config
│   │   │   │   └── variants/         # VPC configuration variants
│   │   │   │       ├── single-az.yaml
│   │   │   │       ├── multi-az.yaml
│   │   │   │       └── transit-gateway.yaml
│   │   │   ├── security-groups/
│   │   │   │   ├── defaults.yaml
│   │   │   │   └── variants/
│   │   │   ├── dns/
│   │   │   └── load-balancers/
│   │   ├── compute/
│   │   │   ├── eks/
│   │   │   │   ├── defaults.yaml
│   │   │   │   ├── production.yaml
│   │   │   │   ├── development.yaml
│   │   │   │   └── variants/
│   │   │   │       ├── standard.yaml
│   │   │   │       ├── gpu-enabled.yaml
│   │   │   │       └── arm-based.yaml
│   │   │   ├── ec2/
│   │   │   ├── lambda/
│   │   │   └── ecs/
│   │   ├── data/
│   │   │   ├── rds/
│   │   │   ├── s3/
│   │   │   ├── elasticache/
│   │   │   └── opensearch/
│   │   ├── security/
│   │   │   ├── iam/
│   │   │   ├── kms/
│   │   │   ├── secrets-manager/
│   │   │   └── certificate-manager/
│   │   └── monitoring/
│   │       ├── cloudwatch/
│   │       ├── prometheus/
│   │       └── grafana/
│   ├── platform/                      # Platform components  
│   │   ├── backstage/
│   │   ├── argocd/
│   │   ├── vault/
│   │   └── external-secrets/
│   └── applications/                   # Application components
│       ├── web-services/
│       ├── apis/
│       ├── data-pipelines/
│       └── ml-workloads/
└── deployments/                       # Actual deployment configurations
    ├── fnx/                           # FNX tenant deployments
    │   ├── development/               # Development account
    │   │   ├── _defaults.yaml         # Account-level defaults
    │   │   ├── us-west-2/             # Primary region
    │   │   │   ├── _defaults.yaml     # Region-level defaults
    │   │   │   ├── testenv-01/        # Environment 1
    │   │   │   │   ├── _stack.yaml    # Stack definition
    │   │   │   │   └── overrides/     # Environment-specific overrides
    │   │   │   │       ├── vpc.yaml
    │   │   │   │       ├── eks.yaml
    │   │   │   │       └── rds.yaml
    │   │   │   └── testenv-02/        # Environment 2
    │   │   │       ├── _stack.yaml
    │   │   │       └── overrides/
    │   │   └── us-east-1/             # Secondary region
    │   │       ├── _defaults.yaml
    │   │       └── dr-env/            # Disaster recovery environment
    │   ├── staging/                   # Staging account
    │   │   ├── _defaults.yaml
    │   │   ├── us-west-2/
    │   │   │   ├── _defaults.yaml
    │   │   │   └── staging-01/
    │   │   │       ├── _stack.yaml
    │   │   │       └── overrides/
    │   │   └── us-east-1/
    │   │       ├── _defaults.yaml
    │   │       └── staging-dr/
    │   └── production/                # Production account
    │       ├── _defaults.yaml
    │       ├── us-west-2/
    │       │   ├── _defaults.yaml
    │       │   ├── prod-01/
    │       │   │   ├── _stack.yaml
    │       │   │   └── overrides/
    │       │   └── prod-02/           # Blue-green deployment
    │       │       ├── _stack.yaml
    │       │       └── overrides/
    │       └── us-east-1/
    │           ├── _defaults.yaml
    │           └── prod-dr/           # Production DR
    ├── acme/                          # ACME tenant deployments
    │   ├── development/
    │   ├── staging/
    │   └── production/
    └── core/                          # Core shared services
        ├── security/                  # Security account
        │   ├── us-west-2/
        │   │   └── central-logging/
        │   └── us-east-1/
        │       └── backup-logging/
        ├── networking/                # Network account
        │   ├── us-west-2/
        │   │   └── transit-hub/
        │   └── us-east-1/
        │       └── transit-hub-dr/
        └── management/                # Management account
            ├── us-west-2/
            │   └── control-tower/
            └── global/
                └── organizations/
```

## 🎯 Key Improvements

### 1. **Logical Separation**
- **Mixins**: Reusable configuration patterns
- **Catalogs**: Component templates and variants  
- **Deployments**: Actual environment implementations

### 2. **Hierarchical Inheritance**
```
Global Settings → Tenant → Account → Region → Environment → Component Overrides
```

### 3. **Standardized Naming**
- Stack names: `{tenant}-{account}-{region}-{environment}`  
- Examples: `fnx-development-us-west-2-testenv-01`, `acme-production-us-east-1-prod-01`

### 4. **Configuration Variants**
- Components support multiple variants (standard, GPU-enabled, ARM-based, etc.)
- Environment-specific optimizations (production vs development)
- Compliance-specific configurations (SOC2, PCI-DSS, HIPAA)

### 5. **Enhanced Validation**
- JSON schemas for all component types
- Stack validation rules
- Compliance framework validation

## 🚀 Usage Examples

### Deploy Development Environment
```bash
# Deploy complete environment
atmos terraform apply-all -s fnx-development-us-west-2-testenv-01

# Deploy specific component  
atmos terraform apply vpc -s fnx-development-us-west-2-testenv-01

# Plan with cost estimation
atmos terraform plan eks -s fnx-development-us-west-2-testenv-01 --detailed-exitcode
```

### Environment Management  
```bash
# List all environments for tenant
atmos describe stacks --filter-by tenant=fnx

# Validate compliance
atmos validate component vpc -s fnx-production-us-west-2-prod-01 --schema soc2

# Check configuration drift
atmos workflow drift-detection tenant=fnx account=production
```

### Multi-Region Deployment
```bash
# Deploy to primary region
atmos workflow deploy-environment tenant=fnx account=production environment=prod-01 region=us-west-2

# Deploy to DR region  
atmos workflow deploy-environment tenant=fnx account=production environment=prod-dr region=us-east-1
```

## 📋 Migration Path

1. **Phase 1**: Create new structure alongside existing
2. **Phase 2**: Migrate development environments  
3. **Phase 3**: Migrate staging environments
4. **Phase 4**: Migrate production environments  
5. **Phase 5**: Remove old structure

## 🔒 Security & Compliance

- **Compliance Frameworks**: Built-in support for SOC2, PCI-DSS, HIPAA, ISO27001
- **Security Baselines**: Enforced through mixins and validation
- **Least Privilege**: IAM configurations follow principle of least privilege
- **Encryption**: All data encrypted at rest and in transit by default
- **Audit Trail**: Complete configuration change tracking

This architecture provides maximum flexibility while maintaining consistency and compliance across all environments.