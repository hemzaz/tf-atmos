# Maintainability Guide

This guide provides best practices for maintaining and extending the Terraform/Atmos codebase.

## Table of Contents

- [Code Organization](#code-organization)
- [Naming Conventions](#naming-conventions)
- [Documentation Standards](#documentation-standards)
- [Variable Management](#variable-management)
- [Component Development](#component-development)
- [Testing Changes](#testing-changes)
- [Troubleshooting](#troubleshooting)

## Code Organization

### Directory Structure

The codebase follows a standard directory structure:

```
tf-atmos/
│
├── components/                # Terraform components
│   └── terraform/             # Terraform modules
│       ├── acm/               # Certificate management
│       ├── eks/               # EKS clusters
│       ├── eks-addons/        # EKS add-ons (Istio, etc.)
│       └── ...                # Other components
│
├── docs/                      # Documentation
│   ├── diagrams/              # Architecture diagrams
│   └── ...                    # Component guides
│
├── examples/                  # Example configurations
│
├── scripts/                   # Utility scripts
│   └── certificates/          # Certificate management scripts
│
├── stacks/                    # Stack configurations
│   ├── account/               # Account-specific stacks
│   │   └── dev/               # Dev account
│   │       └── testenv-01/    # Environment specific configs
│   │
│   ├── catalog/               # Component catalog definitions
│   └── schemas/               # JSON schemas
│
├── templates/                 # Templates for new components
│
└── workflows/                 # Atmos workflow definitions
```

### Where to Find Things

| If you need to... | Look in... |
|-------------------|------------|
| Modify a component | `components/terraform/<component>` |
| Change environment config | `stacks/account/<account>/<environment>/<component>.yaml` |
| Update documentation | `docs/<topic>.md` |
| See component options | `stacks/catalog/<component>.yaml` |
| Find workflow steps | `workflows/<workflow-name>.yaml` |

## Naming Conventions

### Resources

Follow these naming patterns for resources:

* **Components**: Use singular form (e.g., `securitygroup` not `security-groups`)
* **Resources**: Use descriptive names with prefixes (`${local.name_prefix}-<resource-type>`)
* **Variables**: Use descriptive names with common prefixes for related items
* **Outputs**: Use standardized patterns (`<resource>_<attribute>`)

### YAML Files

Stack configuration files follow this naming pattern:

* **Component instances**: `<component-name>.yaml`
* **Stack variables**: `variables.yaml`

## Documentation Standards

### Component Documentation

Every component should include:

1. A README.md file explaining:
   - Purpose of the component
   - Configuration options
   - Usage examples
   - Dependencies

2. Commented code for complex logic:
   ```hcl
   # This complex merge operation combines cluster configurations
   # with their addons, preserving the cluster context for each addon
   addons = merge([
     for cluster_key, cluster in local.clusters : {
       for addon_key, addon in lookup(cluster, "addons", {}) :
         "${cluster_key}.${addon_key}" => merge(addon, { cluster_name = cluster_key })
       if lookup(addon, "enabled", true)
     }
   ]...)
   ```

3. Section headers for logical grouping:
   ```hcl
   # -------------------------------------------------------------
   # Certificate Management
   # -------------------------------------------------------------
   ```

### Variable Documentation

Document all variables with:

1. Clear description
2. Expected format
3. Default values if applicable
4. Validation blocks for constraints

```hcl
variable "domain_name" {
  type        = string
  description = "Domain name for certificates and DNS records (e.g., example.com)"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "The domain_name must be a valid domain (e.g., example.com)."
  }
}
```

## Variable Management

### Stack Variables

Organize variables hierarchically:

1. **Global Variables**: Define common variables in catalog files
2. **Environment Variables**: Override in environment-specific files
3. **Component Variables**: Specific to component instances

Example with overrides:
```yaml
# In catalog/eks.yaml (global)
node_type: "t3.small"

# In account/dev/testenv-01/eks.yaml (environment override)
node_type: "t3.micro"  # Override for dev environment
```

### Variable Precedence

Variables are applied in this order:

1. Component defaults (in variables.tf)
2. Catalog definitions (global)
3. Account/environment overrides
4. Command-line variables

## Component Development

### Adding Features

When extending components:

1. Add new variables to both:
   - Terraform variables.tf
   - Component catalog definition

2. Ensure backward compatibility:
   - Use optional() wrapper for new Terraform variables
   - Provide sensible defaults
   - Mark deprecated variables clearly

3. Update documentation:
   - Document new variables
   - Add examples showing usage

### Using External Files

For complex resources like IAM policies:

1. Store policy JSON in a dedicated files directory:
   ```
   components/terraform/eks-addons/policies/aws-load-balancer-controller-policy.json
   ```

2. Reference via `${file:}` interpolation:
   ```yaml
   service_account_policy: ${file:/components/terraform/eks-addons/policies/aws-load-balancer-controller-policy.json}
   ```

## Testing Changes

### Pre-deployment Testing

Before applying changes:

1. Validate syntax:
   ```bash
   atmos workflow lint
   atmos workflow validate
   ```

2. Check plan:
   ```bash
   atmos terraform plan <component> -s <tenant>-<account>-<environment>
   ```

3. Run non-destructive workflows:
   ```bash
   atmos workflow drift-detection
   ```

### Safe Deployment

Deploy changes safely:

1. Start with non-production environments
2. Use specific component deployments before full environment:
   ```bash
   # Deploy single component first
   atmos terraform apply eks-addons -s tenant-dev-testenv
   
   # Then deploy full environment if successful
   atmos workflow apply-environment tenant=tenant account=dev environment=testenv
   ```

## Troubleshooting

### Debugging Tips

1. Use the troubleshooting guide:
   ```bash
   less docs/troubleshooting-guide.md
   ```

2. Check logs for specific errors:
   ```bash
   # For Terraform state issues
   aws s3 ls s3://terraform-state-bucket/path/to/state
   aws dynamodb get-item --table-name terraform-locks --key '{"LockID":{"S":"path/to/lock"}}'
   
   # For AWS API errors
   aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateCluster
   ```

3. For component-specific issues:
   - Check the component's README.md
   - Look for validation errors in parameter validation blocks
   - Review precondition blocks in resources

### Common Issues

| Problem | Likely Fix |
|---------|------------|
| Certificate validation timeout | Run export-cert.sh to verify certificate status |
| EKS cluster creation stuck | Check subnet tags and IAM role permissions |
| Missing component variable | Verify the variable exists in both variables.tf and catalog YAML |
| Dependencies creating loops | Ensure proper order in stack dependencies section |

---

By following these maintainability guidelines, you'll help ensure the codebase remains clean, consistent, and easy to maintain as it grows.