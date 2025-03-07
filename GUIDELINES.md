# GUIDELINES.md - Guidelines for Terraform/Atmos Codebase

## Commands
- Lint: `atmos workflow lint` (runs terraform fmt and yamllint, and TFSec if installed)
- Validate: `atmos workflow validate` (validates terraform components)
- Plan: `atmos workflow plan-environment tenant=<tenant> account=<account> environment=<environment>`
- Apply: `atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>`
- Drift Detection: `atmos workflow drift-detection`
- Onboard Environment: `atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr>`
- Import Resources: `atmos workflow import` (imports existing resources into Terraform state)
- Test Component: `atmos terraform validate <component> -s <tenant>-<account>-<environment>`
- Diff Changes: `atmos terraform plan <component> -s <tenant>-<account>-<environment> --out=plan.out && terraform show -no-color plan.out > plan.txt`
- Compliance Check: `atmos workflow compliance-check` (generates compliance reports for stack configuration)

## Architecture Overview

### Multi-Account Architecture
- **Account Structure**: 
  - Management Account: For global IAM and billing
  - Shared Services: For common infrastructure services
  - Development, Staging, Production: For application environments
- **Infrastructure Layers**: 
  - Network: VPCs, subnets, gateways
  - Infrastructure: EC2, EKS, RDS
  - Security: IAM, Security Groups
  - Services: API Gateway, Lambda
  - Operations: Monitoring, logging

## Code Style Guidelines

### File Structure
- **Standard Files**: main.tf, variables.tf, outputs.tf, provider.tf, data.tf (optional), locals.tf (optional), policies/ (for JSON templates)
- **Component Structure**: Each component should be self-contained with its own documentation
- **Resource Organization**: Group related resources in functional sections within separate files (e.g., vpc.tf, nat-gateway.tf, route-tables.tf)
- **Nested Structure**: For complex components with submodules, use a nested directory structure

### Naming and Syntax
- **Component Naming**: Use singular form without hyphens (e.g., `securitygroup` not `security-groups`)
- **Resource Naming**: Use `${var.tags["Environment"]}-<resource-type>[-index]` pattern
- **Local Variables**: Use `local.name_prefix` and other locals for consistent naming across resources
- **Casing**: Use snake_case for resources, variables, and outputs
- **Boolean Prefixes**: Use `is_`, `has_`, or `enable_` prefixes for boolean variables
- **Map Keys**: Use consistent key names in maps and objects across components
- **Stack Naming**: Follow `<tenant>-<account>-<environment>` pattern

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
- **Encryption**: Encrypt sensitive data at rest and in transit using customer-managed KMS keys
- **IAM Policies**: Use least privilege IAM policies with specific actions and resources
- **Sensitive Data**: Mark sensitive outputs with `sensitive = true`
- **Secret Management**: Store secrets in SSM Parameter Store or Secrets Manager (`${ssm:/path/to/param}`)
- **Policy Templates**: Use `templatefile()` for policy JSON files, not variable interpolation in JSON
- **Certificate Handling**: 
  - For ACM certificates, use the External Secrets Operator pattern
  - Never store private keys or certificates in Terraform state or source code
- **Security Groups**: Use specific CIDR blocks and ports, avoid 0.0.0.0/0 for inbound rules
- **Instance Security**:
  - Enforce IMDSv2 on all EC2 instances to prevent SSRF attacks
  - Use security-hardened AMIs with proper bootstrapping
- **VPC Flow Logs**: Enable flow logs for all VPCs with analysis in CloudWatch

### Tagging and Organization
- **Standard Tags**: Apply consistent tags to all resources for cost allocation and organization
- **Mandatory Tags**: Include Environment, Name, Project, Owner, ManagedBy, CostCenter, DataClassification, Compliance
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
  - Enable private endpoint for control plane and disable public endpoint
  - Enable control plane logging for all log types
  - Use calico for network policies when required
- **Add-on Configuration**:
  - Standardize on Helm charts for add-on installations
  - Document version compatibility matrices for addons
  - Use appropriate IAM role patterns for service accounts
  - Deploy AWS Load Balancer Controller, ExternalDNS, and Cert-Manager for standard cluster setup
- **Certificate Management**:
  - Use External Secrets Operator for certificate management with Istio
  - Implement automated certificate rotation
  - Store certificates in ACM with proper access controls

### Database Patterns
- **RDS Security**:
  - Store database credentials in Secrets Manager with automatic rotation
  - Use encryption with customer-managed KMS keys for all instances
  - Enable performance insights for monitoring
- **Access Controls**:
  - Deploy databases in private subnets without public access
  - Use IAM authentication when available
  - Implement security groups with strict ingress rules

### Secrets Management
- **Hierarchical Structure**: Organize secrets using `/environment/service/purpose` path structure
- **Automatic Rotation**: Configure automatic rotation intervals according to compliance requirements
- **Access Controls**: Use KMS encryption with context-based access control
- **Kubernetes Integration**: Use External Secrets Operator to sync AWS secrets to Kubernetes

### Testing and Validation
- **Pre-commit Checks**: Run validation before committing with `atmos workflow validate`
- **Module Testing**: Test components in isolation before integration
- **Integration Testing**: Run integration tests for interconnected components
- **Drift Detection**: Run regular drift detection to ensure configuration consistency
- **Security Scanning**: 
  - Run TFSec scans using `atmos workflow lint` if TFSec is installed
  - For additional security scanning, install Checkov with `pip install checkov==3.2.382`
- **Compliance Checks**: Run `atmos workflow compliance-check` to validate stack configuration against best practices

## Compliance Requirements
- **Required Controls**: Implement controls for NIST, PCI, HIPAA, or SOC 2 as needed
- **Automated Checks**: Configure AWS Config rules for automated compliance validation
- **Evidence Collection**: Enable CloudTrail, VPC Flow Logs, GuardDuty, and Security Hub
- **Configuration Management**: Implement configuration drift detection and remediation

## CI/CD Integration
- **Pipeline Integration**: Use included workflow files with Atlantis, Jenkins, or GitHub Actions
- **Pipeline Stages**:
  - Validation: Format check and validation
  - Security: TFSec scans (when installed)
  - Planning: Plan and approval workflow
  - Application: Controlled rollout with failure handling
  - Verification: Post-deployment tests
- **Secure Credentials**: Use assume role patterns for secure pipeline execution
- **Dependency Management**:
  - Use the `.env` file at the root of the repository for all tool version pins
  - Use the install-dependencies.sh script to ensure all required tools are available
  - Use the update-versions.sh script to check for and update tool versions
  - Install optional tools with specific flags (e.g., `--install-checkov`)

## Troubleshooting Guide
- **State Locking Issues**: If experiencing DynamoDB locking errors, check for abandoned locks
  ```bash
  aws dynamodb scan --table-name <dynamo-table-name> --attributes-to-get LockID State
  ```
- **Cross-Account Access**: For permission issues, verify assume_role_arn configuration and trust relationships
- **Stack Drifts**: Run regular drift detection checks to identify manual changes
  ```bash
  atmos workflow drift-detection
  ```
- **Secrets Access Issues**: Verify IAM permissions and KMS key policies
- **EKS Connectivity**: For issues connecting to EKS API:
  - Verify security group allowances
  - Check the AWS authentication chain with `aws eks update-kubeconfig`
  - Verify Kubernetes RBAC permissions