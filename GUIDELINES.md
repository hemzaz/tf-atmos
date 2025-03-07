# GUIDELINES.md - Guidelines for Terraform/Atmos Codebase

## Commands
- Lint: `atmos workflow lint` (runs terraform fmt and yamllint)
- Validate: `atmos workflow validate` (validates terraform components)
- Plan: `atmos workflow plan-environment tenant=<tenant> account=<account> environment=<environment>`
- Apply: `atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>`
- Drift Detection: `atmos workflow drift-detection`
- Onboard Environment: `atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr>`
- Import Resources: `atmos workflow import` (imports existing resources into Terraform state)
- Test Component: `atmos terraform validate <component> -s <tenant>-<account>-<environment>`
- Diff Changes: `atmos terraform plan <component> -s <tenant>-<account>-<environment> --out=plan.out && terraform show -no-color plan.out > plan.txt`

## Code Style Guidelines

### File Structure
- **Standard Files**: main.tf, variables.tf, outputs.tf, provider.tf, data.tf (optional), locals.tf (optional), policies/ (for JSON templates)
- **Component Structure**: Each component should be self-contained with its own documentation
- **Resource Organization**: Group related resources in functional sections within main.tf
- **Nested Structure**: For complex components with submodules, use a nested directory structure

### Naming and Syntax
- **Component Naming**: Use singular form without hyphens (e.g., `securitygroup` not `security-groups`)
- **Resource Naming**: Use `${local.name_prefix}-<resource-type>`, variables use descriptive names
- **Local Variables**: Use `local.name_prefix` and other locals for consistent naming across resources
- **Casing**: Use snake_case for resources, variables, and outputs
- **Boolean Prefixes**: Use `is_`, `has_`, or `enable_` prefixes for boolean variables
- **Map Keys**: Use consistent key names in maps and objects across components

### Input/Output Standards
- **Variables**: 
  - Include detailed descriptions, sensible defaults, and validation blocks for type checking
  - Use standardized types and constraints (e.g., regexes for AWS regions, account IDs)
  - Group related variables with comments
  - Mark sensitive variables with `sensitive = true`
- **Outputs**: 
  - Include resource IDs and ARNs for all created resources
  - Mark sensitive outputs with `sensitive = true`
  - Use consistent output naming patterns (e.g., `<resource>_id`, `<resource>_arn`)
  - Add descriptions to all outputs

### Resource Configuration
- **Dynamic Resources**: Use `for_each` for creating multiple similar resources, `count` for conditionals
- **Resource Dependencies**: Add explicit `depends_on` and appropriate wait times to avoid race conditions
- **Error Handling**: Use lifecycle blocks with preconditions for complex validations
- **Retry Logic**: For resources that may have eventual consistency issues, implement retry logic
- **Configuration Hierarchies**: Use Atmos stack hierarchies for configuration inheritance

### Security Best Practices
- **Encryption**: Encrypt sensitive data at rest and in transit
- **IAM Policies**: Use least privilege IAM policies with specific actions and resources
- **Sensitive Data**: Mark sensitive outputs with `sensitive = true`
- **Secret Management**: Store secrets in SSM Parameter Store or Secrets Manager (`${ssm:/path/to/param}`)
- **Policy Templates**: Use `templatefile()` for policy JSON files, not variable interpolation in JSON
- **Certificate Handling**: 
  - For ACM certificates, use the External Secrets Operator pattern
  - Never store private keys or certificates in Terraform state or source code
- **Security Groups**: Use specific CIDR blocks and ports, avoid 0.0.0.0/0 for inbound rules

### Tagging and Organization
- **Standard Tags**: Apply consistent tags to all resources for cost allocation and organization
- **Mandatory Tags**: Include Environment, Name, Project, Owner, ManagedBy tags
- **Component-Specific Tags**: Add specialized tags for component-specific use cases
- **Tag Variables**: Use variable maps for tags with defaults from context

### Documentation Standards
- **README Files**: Each component must have a README.md with:
  - Component purpose and architecture
  - Required and optional variables
  - Usage examples
  - Integration points
- **Example Configurations**: Include at least one working example in the examples/ directory
- **Comments**: Add descriptive comments for complex logic or non-obvious configurations
- **Architecture Diagrams**: Include diagrams for components with multiple resources or complex relationships

### Multi-Cluster Architecture
- **EKS Best Practices**:
  - Use cluster object map pattern with cluster_name, host, oidc_provider_arn keys
  - Implement proper service account roles for all addons requiring AWS access
  - Apply resource limits and requests for all workloads
- **Add-on Configuration**:
  - Standardize on Helm charts for add-on installations
  - Document version compatibility matrices for addons
  - Use appropriate IAM role patterns for service accounts
- **Certificate Management**:
  - Use External Secrets Operator for certificate management with Istio
  - Implement automated certificate rotation

### Testing and Validation
- **Pre-commit Checks**: Run validation before committing with `atmos workflow validate`
- **Module Testing**: Test components in isolation before integration
- **Integration Testing**: Run integration tests for interconnected components
- **Drift Detection**: Run regular drift detection to ensure configuration consistency

## Troubleshooting Guide
- **State Locking Issues**: If experiencing DynamoDB locking errors, check for abandoned locks
  ```bash
  aws dynamodb scan --table-name <dynamo-table-name> --attributes-to-get LockID State
  ```
- **Cross-Account Access**: For permission issues, verify assume_role_arn configuration and trust relationships