# Stacks Migration Guide

This guide explains how to migrate from the current stack structure to the new enterprise-grade stack architecture.

## Overview

The new stack architecture provides:
- **Hierarchical Organization** - Clear separation of global settings, mixins, catalogs, and deployments
- **Improved Modularity** - Reusable components with environment-specific variations
- **Enhanced Compliance** - Built-in compliance framework support (SOC2, ISO27001)
- **Better Scalability** - Standardized patterns for multi-tenant, multi-region deployments
- **Cost Optimization** - Environment-appropriate resource configurations

## New Architecture Structure

```
stacks-new/
├── _globals/               # Global configuration applied to all stacks
│   ├── globals.yaml       # Universal settings and imports
│   └── settings/          # Shared configuration modules
├── mixins/                # Reusable configuration mixins
│   ├── accounts/          # Account-level settings (dev, staging, prod)
│   ├── regions/           # Region-specific settings (us-west-2, us-east-1)
│   ├── environments/      # Environment configurations (testenv-01, staging)
│   └── compliance/        # Compliance frameworks (soc2, iso27001)
├── catalogs/              # Standardized component configurations
│   ├── foundation/        # Infrastructure foundations (VPC, security)
│   ├── platform/          # Platform services (EKS, databases)
│   ├── application/       # Application components
│   └── observability/     # Monitoring and observability
└── deployments/           # Actual stack configurations
    └── fnx/               # Tenant-specific deployments
        ├── dev/           # Development account stacks
        ├── staging/       # Staging account stacks
        └── prod/          # Production account stacks
```

## Migration Steps

### Phase 1: Preparation

1. **Backup Current Configuration**
   ```bash
   cp -r stacks stacks-backup
   ```

2. **Review Current Stacks**
   ```bash
   atmos list stacks
   ```

3. **Document Environment Variables**
   - Document any environment-specific variables
   - Note compliance requirements
   - Identify shared configurations

### Phase 2: Configuration Mapping

Map your current stacks to the new architecture:

#### Current Stack → New Structure Mapping

| Current Stack | New Structure |
|---------------|---------------|
| `fnx-testenv-01-dev` | `deployments/fnx/dev/us-west-2/testenv-01.yaml` |
| `fnx-staging-staging` | `deployments/fnx/staging/us-west-2/staging.yaml` |
| `fnx-prod-production` | `deployments/fnx/prod/us-west-2/production.yaml` |

#### Configuration Migration

1. **Global Settings**
   - Move shared configurations to `_globals/globals.yaml`
   - Extract common variables to settings files

2. **Account-Level Settings**
   - Development configurations → `mixins/accounts/development.yaml`
   - Production configurations → `mixins/accounts/production.yaml`

3. **Region Settings**
   - Region-specific settings → `mixins/regions/us-west-2.yaml`
   - DR region settings → `mixins/regions/us-east-1.yaml`

4. **Environment Settings**
   - Test environment → `mixins/environments/testenv-01.yaml`
   - Staging environment → `mixins/environments/staging.yaml`

### Phase 3: Component Migration

#### VPC Component Migration

**Old Configuration:**
```yaml
# In stack file
components:
  terraform:
    vpc:
      vars:
        cidr_block: "10.0.0.0/16"
        # ... other vars
```

**New Configuration:**
```yaml
# In deployment file
imports:
  - "catalogs/foundation/vpc"
  
components:
  terraform:
    vpc:
      vars:
        cidr_block: "10.0.0.0/16"  # Override catalog default
```

#### EKS Component Migration

**Old Configuration:**
```yaml
components:
  terraform:
    eks:
      vars:
        cluster_version: "1.28"
        node_groups: {...}
```

**New Configuration:**
```yaml
imports:
  - "catalogs/platform/eks"
  
components:
  terraform:
    eks:
      # Inherits environment-appropriate defaults from catalog
      vars:
        cluster_name: "${tenant}-${environment}-eks"
```

### Phase 4: Validation

1. **Syntax Validation**
   ```bash
   find stacks-new -name "*.yaml" -exec yamllint {} \;
   ```

2. **Configuration Validation**
   ```bash
   atmos validate stacks --stacks-dir=stacks-new
   ```

3. **Component Validation**
   ```bash
   atmos terraform validate vpc -s fnx-dev-us-west-2-testenv-01 --stacks-dir=stacks-new
   ```

### Phase 5: Testing

1. **Plan Generation**
   ```bash
   # Test with new structure
   atmos terraform plan vpc -s fnx-dev-us-west-2-testenv-01 --stacks-dir=stacks-new
   
   # Compare with current structure
   atmos terraform plan vpc -s fnx-testenv-01-dev --stacks-dir=stacks
   ```

2. **Output Comparison**
   - Compare Terraform plans between old and new structures
   - Ensure resource configurations are equivalent
   - Verify tags and naming conventions

### Phase 6: Deployment

1. **Update Atmos Configuration**
   ```yaml
   # In atmos.yaml
   stacks:
     base_path: "stacks-new"
   ```

2. **Gradual Migration**
   - Start with non-production environments
   - Test thoroughly in each environment
   - Migrate production last

3. **State Management**
   - Ensure Terraform state bucket configurations match
   - Verify state locking is working
   - Test state operations

## Key Benefits

### 1. Environment Consistency
- Consistent configurations across environments
- Standardized resource sizing and security settings
- Automated compliance configuration

### 2. Cost Optimization
- Environment-appropriate resource configurations
- Automated spot instance usage in development
- Scheduled shutdown for non-production environments

### 3. Security & Compliance
- Built-in compliance frameworks (SOC2, ISO27001)
- Standardized security configurations
- Consistent encryption and access controls

### 4. Operational Excellence
- Standardized monitoring and alerting
- Consistent backup and disaster recovery
- Improved troubleshooting with consistent patterns

## Configuration Examples

### Environment-Specific Resource Sizing

**Development:**
```yaml
# Automatically configured via development mixin
- t3.micro, t3.small instances
- Single NAT gateway
- Spot instances for cost savings
- Basic monitoring
```

**Production:**
```yaml
# Automatically configured via production mixin  
- m5.large, m5.xlarge instances
- Multi-AZ NAT gateways
- On-demand instances for reliability
- Enhanced monitoring with alerting
```

### Compliance Integration

**SOC2 Compliance:**
```yaml
imports:
  - "mixins/compliance/soc2"
  
# Automatically enables:
# - 7-year log retention
# - Enhanced access logging  
# - MFA requirements
# - Audit trail monitoring
```

## Common Migration Issues

### 1. Variable Resolution
**Issue:** Variables not resolving correctly
**Solution:** Check import order - globals first, then mixins, then catalogs

### 2. Circular Dependencies
**Issue:** Import loops between configuration files
**Solution:** Use proper hierarchy - globals → mixins → catalogs → deployments

### 3. Override Conflicts
**Issue:** Configuration values being overridden unexpectedly
**Solution:** Check variable precedence - later imports override earlier ones

## Rollback Plan

If migration issues occur:

1. **Immediate Rollback**
   ```bash
   # Revert atmos.yaml to use old stacks directory
   stacks:
     base_path: "stacks"
   ```

2. **Gradual Rollback**
   - Test individual stacks before full rollback
   - Use old stack names with `--stacks-dir=stacks`

3. **State Recovery**
   ```bash
   # If state issues occur, restore from backup
   aws s3 cp s3://terraform-state-bucket/backup/ s3://terraform-state-bucket/ --recursive
   ```

## Validation Checklist

- [ ] All current stacks have equivalent new configurations
- [ ] Variable resolution works correctly
- [ ] Component outputs are accessible
- [ ] Terraform plans are equivalent
- [ ] State management is working
- [ ] Compliance requirements are met
- [ ] Cost optimization is working
- [ ] Monitoring and alerting are configured
- [ ] Backup and disaster recovery are set up

## Post-Migration

1. **Update Documentation**
   - Update deployment guides
   - Update runbooks and procedures
   - Train team on new structure

2. **Cleanup**
   ```bash
   # After successful migration
   rm -rf stacks-backup
   rm -rf stacks  # Keep old structure until fully confident
   ```

3. **Continuous Improvement**
   - Monitor for issues in the new structure
   - Gather feedback from team
   - Refine configurations based on usage

## Support

For migration issues:
1. Review this guide thoroughly
2. Check existing configurations in the new structure
3. Validate step-by-step using the testing procedures
4. Ensure proper import order and variable resolution