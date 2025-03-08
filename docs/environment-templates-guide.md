# Environment Templates Guide

This guide describes the available environment templates and how to use them to create new environments quickly and consistently.

## Available Templates

We provide the following environment templates, each optimized for specific use cases:

| Template | Purpose | Key Features | Best For |
|----------|---------|--------------|----------|
| **Dev** | Development environments | Cost-optimized, relaxed security | Individual developers, feature branches |
| **Staging** | Pre-production validation | Production-like, optimized costs | Final verification before production |
| **Prod** | Production workloads | High availability, strict security | Customer-facing applications, critical services |
| **QA** | Testing and validation | Testing tools, production-like | Test automation, integration testing |
| **Demo** | Demonstrations | Pre-loaded data, scheduled shutdown | Sales demos, training, PoCs |
| **Data** | Data processing | Storage optimized, data services | Analytics, ETL pipelines, ML workloads |

## Using Templates

### Command-Line Interface

The easiest way to create a new environment is with the provided script:

```bash
# Basic usage
./scripts/create-environment.sh \
  --template dev \
  --tenant mycompany \
  --account dev \
  --environment dev-01 \
  --vpc-cidr 10.0.0.0/16

# Production example with custom region
./scripts/create-environment.sh \
  --template prod \
  --tenant mycompany \
  --account prod \
  --environment prod-01 \
  --vpc-cidr 10.0.0.0/16 \
  --region us-east-1
  
# Data environment with RDS enabled
./scripts/create-environment.sh \
  --template data \
  --tenant mycompany \
  --account data \
  --environment data-01 \
  --vpc-cidr 10.0.0.0/16 \
  --rds true
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--template`, `-t` | Template type (dev, prod, qa, demo, data) | dev |
| `--tenant` | Tenant name (organization name) | (required) |
| `--account` | AWS account name/id | (required) |
| `--environment` | Environment name (should follow name-## pattern) | (required) |
| `--vpc-cidr` | VPC CIDR block | (required) |
| `--region` | AWS region | us-west-2 |
| `--eks` | Enable EKS cluster | true |
| `--rds` | Enable RDS database | false |
| `--target-dir` | Custom output directory | ./stacks/account/ACCOUNT/ENVIRONMENT |
| `--force` | Overwrite existing environment | false |
| `--show-only` | Show what would be created without creating files | false |

## Integration with Atmos Workflows

You can also integrate the template creation into your Atmos workflows:

```yaml
# workflows/create-template-environment.yaml
name: create-template-environment
description: "Create an environment from a predefined template"

workflows:
  create:
    description: "Create a new environment from template"
    steps:
    - run:
        command: |
          # Validate required variables
          if [ -z "${tenant}" ] || [ -z "${account}" ] || [ -z "${environment}" ] || [ -z "${vpc_cidr}" ]; then
            echo "ERROR: Missing required parameters."
            echo "Usage: atmos workflow create-template-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr> [template=<template>] [region=<region>]"
            exit 1
          fi
          
          # Set defaults
          TEMPLATE="${template:-dev}"
          REGION="${region:-us-west-2}"
          
          # Create the environment
          ./scripts/create-environment.sh \
            --template "$TEMPLATE" \
            --tenant "$tenant" \
            --account "$account" \
            --environment "$environment" \
            --vpc-cidr "$vpc_cidr" \
            --region "$REGION"
          
          echo "Environment ${tenant}-${account}-${environment} created from template ${TEMPLATE}."
          echo "Use the following commands to deploy:"
          echo "  atmos terraform plan vpc -s ${tenant}-${account}-${environment}"
          echo "  atmos workflow apply-environment tenant=${tenant} account=${account} environment=${environment}"
```

## Template Customization

### Directory Structure

Each template is stored in `templates/environments/<template_type>/` with the following structure:

```
templates/environments/dev/
├── README.md                # Template documentation
├── stacks/                  # Optional stack configurations
└── variables.yaml           # Default variables
```

### Customizing Templates

To customize a template:

1. Copy an existing template to a new directory:
   ```bash
   cp -r templates/environments/dev templates/environments/custom
   ```

2. Modify the `variables.yaml` file to set your defaults

3. Update the `README.md` with appropriate documentation

4. Use your custom template:
   ```bash
   ./scripts/create-environment.sh -t custom ...
   ```

## Template Variables

Each template includes default variables appropriate for that environment type. Here are some key variables available across templates:

### Common Variables

| Variable | Description |
|----------|-------------|
| vpc.cidr_block | CIDR block for the VPC |
| vpc.max_subnet_count | Maximum number of subnets to create |
| vpc.single_nat_gateway | Whether to use a single NAT gateway |
| vpc.vpc_flow_logs_enabled | Whether to enable VPC flow logs |
| compute.eks_enabled | Whether to enable EKS |
| compute.eks_node_instance_type | Instance type for EKS nodes |
| compute.eks_node_min_count | Minimum number of EKS nodes |
| security.compliance_level | Compliance level (basic, soc2, hipaa, pci) |
| security.log_retention_days | Number of days to retain logs |
| monitoring.detailed_monitoring_enabled | Whether to enable detailed CloudWatch monitoring |

### Template-Specific Variables

Each template also includes variables specific to its purpose:

- **Dev**: Simplified security, cost-optimized resources
- **Prod**: Enhanced security, high availability, comprehensive monitoring
- **QA**: Testing tools, automation capabilities
- **Demo**: Demonstration data, scheduled shutdown
- **Data**: Data processing optimizations, storage configurations

## Best Practices

1. **Naming Conventions**: Use consistent environment naming (e.g., dev-01, qa-02, prod-01)
2. **CIDR Planning**: Plan your VPC CIDR blocks carefully to avoid overlaps
3. **Template Selection**: Choose the appropriate template for your use case
4. **Customization**: Create custom templates for recurring specialized environments
5. **Version Control**: Commit generated environments to version control
6. **Documentation**: Add environment-specific details to the generated README.md
7. **Testing**: Validate new environments before deploying to AWS

## Troubleshooting

### Common Issues

- **Template Not Found**: Ensure the template name is correct and exists in `templates/environments/`
- **Invalid CIDR**: Ensure the VPC CIDR block is in the format `x.x.x.x/y`
- **Environment Already Exists**: Use `--force` to overwrite or specify a different environment name
- **Missing Variables**: Ensure all required variables are provided

### Getting Help

For additional help:

```bash
./scripts/create-environment.sh --help
```