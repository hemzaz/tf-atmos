# Atmos Environment Templating

This directory contains the Copier template for creating new Atmos environments following the organizational stack structure.

## Stack Structure

This template generates environments using the following structure:

```
stacks/
└── orgs/
    └── {tenant}/
        └── {account}/
            └── {region}/
                └── {env_name}/
                    ├── main.yaml
                    └── components/
                        ├── globals.yaml
                        ├── networking.yaml
                        ├── security.yaml
                        ├── compute.yaml
                        └── services.yaml
```

## Using the Template

The template can be used in two ways:

### 1. Using Python CLI (Recommended)

```bash
# Create a new environment
gaia template create-environment --tenant acme --account dev --region us-east-1 --environment test-01 --vpc-cidr 10.0.0.0/16

# Update an existing environment with template changes
gaia template update-environment --tenant acme --account dev --region us-east-1 --environment test-01

# List available templates
gaia template list
```

### 2. Using Atmos Workflows

```bash
# Create a new environment
atmos workflow template-environment create-environment tenant=acme account=dev region=us-east-1 environment=test-01 vpc-cidr=10.0.0.0/16

# Update an existing environment
atmos workflow template-environment update-environment tenant=acme account=dev region=us-east-1 environment=test-01

# Create and apply a new environment in one step
atmos workflow template-environment onboard-environment tenant=acme account=dev region=us-east-1 environment=test-01 vpc-cidr=10.0.0.0/16
```

## Template Variables

The template supports the following variables:

| Variable | Description | Default |
|----------|-------------|---------|
| tenant | Organization tenant name | mycompany |
| account | AWS account name (e.g., dev, staging, prod) | dev |
| aws_region | AWS region for this environment | us-west-2 |
| env_name | Environment name (e.g., test-01) | test-01 |
| env_type | Environment type (affects resource sizing) | development |
| vpc_cidr | VPC CIDR block | 10.0.0.0/16 |
| availability_zones | List of availability zones | ["us-west-2a", "us-west-2b", "us-west-2c"] |
| eks_cluster | Enable EKS cluster | true |
| eks_node_instance_type | EKS node instance type | t3.medium |
| eks_node_min_count | Minimum number of EKS nodes | 2 |
| eks_node_max_count | Maximum number of EKS nodes | 5 |
| rds_instances | Enable RDS instances | false |
| enable_logging | Enable centralized logging | true |
| enable_monitoring | Enable monitoring | true |
| compliance_level | Compliance requirements level (basic, soc2, hipaa, pci) | basic |
| team_email | Team email for notifications | team@example.com |

## Customizing the Template

To customize the template:

1. Edit the `copier.yml` file to modify variables, defaults, or validation rules
2. Update the template files in the `{{env_name}}/stacks/orgs/` directory
3. Modify the hooks in the `hooks/` directory for pre/post processing

## Generated Structure

The template generates the following component configuration files:

1. **globals.yaml**: Global settings, backend configuration, IAM roles
2. **networking.yaml**: VPC, subnets, security groups
3. **security.yaml**: ACM certificates, security resources
4. **compute.yaml**: EKS cluster configuration (if enabled)
5. **services.yaml**: EKS addons, RDS instances (if enabled)

This organization follows the standard component patterns and properly inherits from the existing configuration hierarchy.

## Python Integration

The template is now fully integrated with the Python-based Atmos CLI, providing:

1. Programmatic access to Copier templating
2. Consistent error handling and validation
3. Integration with the Atmos workflow system
4. Command-line interfaces via Typer
5. Optional automation for environment onboarding