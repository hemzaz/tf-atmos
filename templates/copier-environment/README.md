# Atmos Environment Templating

This directory contains the Copier template for creating new Atmos environments.

## Using the Template

The template can be used in two ways:

### 1. Using Python CLI (Recommended)

```bash
# Create a new environment
atmos-cli template create-environment --tenant acme --account dev --environment us-east-1 --vpc-cidr 10.0.0.0/16

# Update an existing environment with template changes
atmos-cli template update-environment --tenant acme --account dev --environment us-east-1

# List available templates
atmos-cli template list
```

### 2. Using Atmos Workflows

```bash
# Create a new environment
atmos workflow template-environment create-environment tenant=acme account=dev environment=us-east-1 vpc-cidr=10.0.0.0/16

# Update an existing environment
atmos workflow template-environment update-environment tenant=acme account=dev environment=us-east-1

# Create and apply a new environment in one step
atmos workflow template-environment onboard-environment tenant=acme account=dev environment=us-east-1 vpc-cidr=10.0.0.0/16
```

## Template Variables

The template supports the following variables:

| Variable | Description | Default |
|----------|-------------|---------|
| tenant | Organization tenant name | mycompany |
| account | AWS account name (e.g., dev, staging, prod) | dev |
| env_name | Environment name (e.g., test-01) | test-01 |
| env_type | Environment type (affects resource sizing) | development |
| aws_region | AWS region for this environment | us-west-2 |
| vpc_cidr | VPC CIDR block | 10.0.0.0/16 |
| availability_zones | List of availability zones | ["us-west-2a", "us-west-2b", "us-west-2c"] |
| eks_cluster | Enable EKS cluster | true |
| rds_instances | Enable RDS instances | false |
| enable_logging | Enable centralized logging | true |
| enable_monitoring | Enable monitoring | true |
| compliance_level | Compliance requirements level | basic |
| team_email | Team email for notifications | team@example.com |

## Customizing the Template

To customize the template:

1. Edit the `copier.yml` file to modify variables, defaults, or validation rules
2. Update the template files in the `{{env_name}}` directory
3. Modify the hooks in the `hooks/` directory for pre/post processing

## Python Integration

The template is now fully integrated with the Python-based Atmos CLI, providing:

1. Programmatic access to Copier templating
2. Consistent error handling and validation
3. Integration with the Atmos workflow system
4. Command-line interfaces via Typer
5. Optional automation for environment onboarding