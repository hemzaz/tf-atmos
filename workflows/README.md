# Atmos Workflows

This directory contains Atmos workflow definitions for common infrastructure operations. These workflows are designed to simplify complex operations by providing standardized, repeatable processes.

## Available Workflows

| Workflow | Description | Command |
|----------|-------------|---------|
| apply-backend | Apply changes to the Terraform backend infrastructure | `atmos workflow apply-backend tenant=<tenant> region=<region>` |
| apply-environment | Apply changes for all components in an environment | `atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment> [auto_approve=true|false] [parallel=true|false]` |
| bootstrap-backend | Initialize the Terraform backend (S3 bucket and DynamoDB table) | `atmos workflow bootstrap-backend tenant=<tenant> region=<region> [bucket_suffix=<suffix>] [dynamodb_suffix=<suffix>]` |
| compliance-check | Run security and compliance checks on your infrastructure | `atmos workflow compliance-check tenant=<tenant> account=<account> environment=<environment>` |
| create-environment-template | Create a new environment from templates | `atmos workflow create-environment-template tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr> [region=<region>] [env_type=<type>]` |
| destroy-backend | Destroy the Terraform backend infrastructure | `atmos workflow destroy-backend tenant=<tenant> region=<region> [confirm=true]` |
| destroy-environment | Destroy all components in an environment | `atmos workflow destroy-environment tenant=<tenant> account=<account> environment=<environment> [auto_approve=true|false] [safe_destroy=true|false]` |
| drift-detection | Detect infrastructure drift in an environment | `atmos workflow drift-detection tenant=<tenant> account=<account> environment=<environment> [parallel=true|false]` |
| import | Import existing resources into Terraform | `atmos workflow import tenant=<tenant> account=<account> environment=<environment> component=<component> resource_address=<addr> resource_id=<id>` |
| lint | Run linters on Terraform code and configuration files | `atmos workflow lint [fix=true|false] [skip_security=true|false]` |
| onboard-environment | Onboard a new environment with infrastructure | `atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr> [region=<region>] [env_type=<type>] [auto_deploy=true|false]` |
| plan-environment | Plan changes for all components in an environment | `atmos workflow plan-environment tenant=<tenant> account=<account> environment=<environment> [output_dir=<dir>] [parallel=true|false]` |
| rotate-certificate | Rotate certificates in Secrets Manager and ACM | `atmos workflow rotate-certificate secret_name=<secret> namespace=<namespace> [acm_arn=<acm_cert_arn>]` |
| state-operations | Manage Terraform state operations | `atmos workflow state-operations action=<list|detect|clean> tenant=<tenant> account=<account> environment=<environment> [older_than=<minutes>] [force=true|false]` |
| update-environment-template | Update an existing environment with template changes | `atmos workflow update-environment-template tenant=<tenant> account=<account> environment=<environment>` |
| validate | Validate components in an environment | `atmos workflow validate tenant=<tenant> account=<account> environment=<environment> [parallel=true|false]` |

## Common Parameters

Most workflows accept the following common parameters:

- `tenant`: Organization or project identifier (e.g., "acme")
- `account`: AWS account identifier (e.g., "dev", "staging", "prod")
- `environment`: Environment name (e.g., "us-east-1", "eu-west-1")
- `auto_approve`: Skip interactive approval (true/false)
- `parallel`: Run operations in parallel when possible (true/false)

## Detailed Usage Examples

### Environment Provisioning

```bash
# Create a new environment
atmos workflow create-environment-template tenant=acme account=dev environment=us-east-1 vpc_cidr=10.0.0.0/16 region=us-east-1 env_type=development

# Onboard a complete environment (create template and deploy)
atmos workflow onboard-environment tenant=acme account=dev environment=us-east-1 vpc_cidr=10.0.0.0/16 auto_deploy=true

# Plan changes to an environment
atmos workflow plan-environment tenant=acme account=dev environment=us-east-1 output_dir=./plans

# Apply changes to an environment
atmos workflow apply-environment tenant=acme account=dev environment=us-east-1 auto_approve=false parallel=true

# Validate components in an environment
atmos workflow validate tenant=acme account=dev environment=us-east-1 parallel=true
```

### Backend Management

```bash
# Bootstrap a new Terraform backend
atmos workflow bootstrap-backend tenant=acme region=us-east-1 bucket_suffix=terraform-state dynamodb_suffix=terraform-locks

# Apply changes to backend infrastructure
atmos workflow apply-backend tenant=acme region=us-east-1

# Destroy backend infrastructure (USE WITH CAUTION)
atmos workflow destroy-backend tenant=acme region=us-east-1 confirm=true
```

### Maintenance Operations

```bash
# Detect drift in an environment
atmos workflow drift-detection tenant=acme account=dev environment=us-east-1 parallel=true

# Import existing resources
atmos workflow import tenant=acme account=dev environment=us-east-1 component=vpc resource_address=aws_vpc.main resource_id=vpc-12345

# List state locks
atmos workflow state-operations action=list tenant=acme account=dev environment=us-east-1

# Clean abandoned state locks
atmos workflow state-operations action=clean tenant=acme account=dev environment=us-east-1 older_than=120 force=false
```

### Quality Assurance

```bash
# Run linters with automatic fixing
atmos workflow lint fix=true

# Run linters without security scanning
atmos workflow lint skip_security=true

# Validate components
atmos workflow validate tenant=acme account=dev environment=us-east-1
```

### Certificate Management

```bash
# Rotate certificate in Secrets Manager and ACM
atmos workflow rotate-certificate secret_name=example-com namespace=cert-manager acm_arn=arn:aws:acm:us-east-1:123456789012:certificate/abcd1234
```

## Core Components

The workflow system uses several reusable components:

1. **Component Discovery**: Automatically discovers components in an environment, analyzes their dependencies, and sorts them in the correct order
2. **Component Operations**: Provides operations (apply, plan, validate, destroy, drift) on components
3. **State Management**: Manages Terraform state locks and helps resolve locking issues
4. **Certificate Rotation**: Securely handles certificate rotation and deployment

## Design Principles

1. **Separation of Concerns** - YAML files define the interface, implementation contains the logic
2. **DRY (Don't Repeat Yourself)** - Common logic is extracted into utility functions
3. **Self-Documentation** - Clear parameter names and descriptions
4. **Consistency** - Common parameter names and formats across workflows
5. **Progressive Enhancement** - Basic operations work in non-interactive mode, with additional features in interactive mode
6. **Dynamic Discovery** - Components and their dependencies are automatically discovered and ordered
7. **Error Handling** - Robust error handling with clear messaging and proper exit codes

## Error Handling

All workflows are designed to fail fast and return appropriate exit codes:
- 0: Success
- 1: Error during execution
- 2: Invalid parameters or prerequisites not met

## Environment Variables

Some workflows may use the following environment variables:
- `AWS_PROFILE`: AWS profile to use for authentication
- `AWS_REGION`: Default AWS region
- `MANAGEMENT_ACCOUNT_ID`: AWS management account ID for cross-account operations
- `ALARM_EMAIL`: Email address for CloudWatch Alarms