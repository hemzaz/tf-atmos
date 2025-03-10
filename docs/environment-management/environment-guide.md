# Environment Management Guide

_Last Updated: March 10, 2025_

This comprehensive guide covers all aspects of environment management with Atmos, including environment creation, templating, onboarding, management workflows, and troubleshooting.

## Table of Contents

1. [Concepts](#concepts)
2. [Environment Templates](#environment-templates)
   - [Available Templates](#available-templates)
   - [Template Implementation](#template-implementation)
   - [Template Structure](#template-structure)
   - [Template Variables](#template-variables)
3. [Environment Creation](#environment-creation)
   - [Prerequisites](#prerequisites)
   - [Using the CLI](#using-the-cli)
   - [Using Atmos Workflows](#using-atmos-workflows)
   - [Available Options](#available-options)
4. [Environment Workflows](#environment-workflows)
   - [Environment Onboarding](#environment-onboarding)
   - [Environment Creation](#environment-creation-workflow)
   - [Environment Updates](#environment-updates)
   - [Environment Deployment](#environment-deployment)
5. [Certificate Management](#certificate-management)
   - [Certificate Creation](#certificate-creation)
   - [Certificate Rotation](#certificate-rotation)
   - [Integration with External Secrets](#integration-with-external-secrets)
6. [Environment Structure](#environment-structure)
   - [Directory Organization](#directory-organization)
   - [Configuration Hierarchy](#configuration-hierarchy)
   - [Component Structure](#component-structure)
7. [Best Practices](#best-practices)
   - [Naming Conventions](#naming-conventions)
   - [CIDR Planning](#cidr-planning)
   - [Template Selection](#template-selection)
   - [Security](#security)
   - [Documentation](#documentation)
   - [Testing](#testing)
8. [Troubleshooting](#troubleshooting)
   - [Common Issues](#common-issues)
   - [Verification Commands](#verification-commands)
   - [Logging](#logging)
   - [Getting Help](#getting-help)
9. [Reference](#reference)
   - [Environment Variables](#environment-variables)
   - [Commands Reference](#commands-reference)
   - [Related Resources](#related-resources)

## Concepts

Atmos environments combine multiple infrastructure components to create complete deployment targets (development, staging, production). Each environment has:

1. **Infrastructure definition** - Components and their configuration
2. **Context variables** - Environment-specific settings (region, VPC CIDR, etc.)
3. **State storage** - Terraform state in S3/DynamoDB
4. **IAM roles** - Permissions for deployment and operations
5. **Monitoring** - CloudWatch dashboards and alarms

## Environment Templates

We use templates to standardize environment creation and ensure consistency across deployments. Templates provide pre-configured infrastructure for common use cases while allowing customization.

### Available Templates

We provide environment templates optimized for specific use cases:

| Template | Purpose | Key Features | Best For |
|----------|---------|--------------|----------|
| **Dev** | Development | Cost-optimized, relaxed security, ephemeral workloads | Feature development, testing, experimentation |
| **Staging** | Pre-production | Production-like, optimized costs, reduced redundancy | Integration testing, final verification |
| **Prod** | Production | High availability, strict security, multi-AZ | Customer-facing workloads, mission-critical systems |
| **Data** | Data processing | Storage optimized, data services, batch processing | Analytics, ETL, ML, data warehousing |
| **Shared** | Shared services | Central services, cross-account access | Authentication, logging, monitoring |

Each template includes default components appropriate for its use case:

| Component | Dev | Staging | Prod | Data | Shared |
|-----------|-----|---------|------|------|--------|
| VPC | ✓ | ✓ | ✓ | ✓ | ✓ |
| EKS | ✓ | ✓ | ✓ | ✓ | ✓ |
| RDS | - | ✓ | ✓ | ✓ | - |
| Monitoring | Basic | Standard | Advanced | Standard | Advanced |
| IAM | Basic | Standard | Strict | Standard | Central |
| Secrets | Local | Managed | Managed | Managed | Central |
| Backups | - | Basic | Advanced | Advanced | Basic |
| DNS | Subdomain | Subdomain | Root domain | Subdomain | Root domain |

### Template Implementation

We use [Copier](https://copier.readthedocs.io/) for environment templating, which provides:

1. **Two-way updates** - Environments can be updated when templates change
2. **Git integration** - Templates stored in Git with versioning
3. **Jinja2 templating** - Powerful conditional logic
4. **Interactive prompts** - User-friendly environment customization

#### Installation

To use Copier for template management:

```bash
# Install Copier
pip install copier

# Check installation
copier --version
```

#### Comparison with Other Tools

| Tool | Pros | Cons | Best For |
|------|------|------|----------|
| **Copier** | Two-way updates, Git integration, Jinja2 | Python dependency | Complete environments |
| **Yeoman** | JavaScript ecosystem, generators | One-way only | Frontend projects |
| **Cookiecutter** | Simple, Python-based | One-way only | Simple templates |
| **Custom Scripts** | Full control | Maintenance burden | Specialized needs |

### Template Structure

Templates are stored in the `templates/copier-environment/` directory with the following structure:

```
templates/copier-environment/
├── README.md                  # Template documentation
├── copier.yml                 # Template configuration
├── hooks/                     # Pre/post generation hooks
│   ├── post_gen.py            # Post-generation script
│   ├── pre_gen.py             # Pre-generation script
│   └── utility.py             # Utility functions
└── {{env_name}}/              # Template content (uses Jinja2 syntax)
    ├── README.md              # Environment documentation
    └── stacks/                # Stack configurations
        └── {{tenant}}/        # Tenant directory (templated)
            └── {{account}}/   # Account directory (templated)
                └── {{env_name}}/ # Environment directory (templated)
                    ├── eks.yaml      # EKS configuration
                    ├── main.yaml     # Main configuration
                    ├── networking.yaml # Networking configuration
                    └── variables.yaml # Environment variables
```

#### copier.yml Example

```yaml
# Template configuration
_min_copier_version: "7.0.0"
_envops:
  ignore_undefined: false
  keep_trailing_newline: true

# Questions
tenant:
  type: str
  help: Tenant/organization name
  validator: "^[a-zA-Z][a-zA-Z0-9-]+$"

account:
  type: str
  help: AWS account name
  validator: "^[a-zA-Z][a-zA-Z0-9-]+$"

env_name:
  type: str
  help: Environment name
  validator: "^[a-zA-Z][a-zA-Z0-9-]+$"

env_type:
  type: str
  help: Environment type
  choices:
    - development
    - staging
    - production
  default: development

vpc_cidr:
  type: str
  help: VPC CIDR block
  default: 10.0.0.0/16
  validator: "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\\/([0-9]|[1-2][0-9]|3[0-2]))$"

aws_region:
  type: str
  help: AWS region
  default: us-west-2
  choices:
    - us-east-1
    - us-east-2 
    - us-west-1
    - us-west-2
    - eu-west-1
    - eu-west-2
    - eu-central-1
    - ap-southeast-1
    - ap-southeast-2

eks_enabled:
  type: bool
  help: Enable EKS cluster
  default: true

rds_enabled:
  type: bool
  help: Enable RDS database
  default: false

# Tasks
_tasks:
  - "chmod +x {{env_name}}/scripts/*.sh"
```

### Template Variables

Templates support various variables for customization:

#### Core Variables

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `tenant` | Tenant/organization name | (required) | `^[a-zA-Z][a-zA-Z0-9-]+$` |
| `account` | AWS account name | (required) | `^[a-zA-Z][a-zA-Z0-9-]+$` |
| `env_name` | Environment name | (required) | `^[a-zA-Z][a-zA-Z0-9-]+$` |
| `env_type` | Environment type | development | choices: development, staging, production |
| `vpc_cidr` | VPC CIDR block | 10.0.0.0/16 | CIDR format validation |
| `aws_region` | AWS region | us-west-2 | Valid AWS region |

#### Component Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `eks_enabled` | Enable EKS cluster | true |
| `rds_enabled` | Enable RDS database | false |
| `monitoring_enabled` | Enable monitoring | true |
| `secrets_manager_enabled` | Enable Secrets Manager | true |
| `vpc_flow_logs_enabled` | Enable VPC Flow Logs | true |

#### Advanced Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `eks_version` | EKS version | 1.28 |
| `vpc_public_subnets` | Number of public subnets | 3 |
| `vpc_private_subnets` | Number of private subnets | 3 |
| `vpc_enable_nat_gateway` | Enable NAT Gateway | true |
| `vpc_single_nat_gateway` | Use single NAT Gateway | false |

## Environment Creation

### Prerequisites

Before creating a new environment, ensure you have:

1. **AWS Account Setup**
   - AWS account created and configured
   - IAM user or role with appropriate permissions
   - AWS CLI configured with credentials

2. **Tools Installation**
   - Atmos CLI installed
   - Terraform installed
   - Python 3.8+ with pip
   - Copier installed

3. **Repository Access**
   - Access to the repository
   - Latest code pulled from the main branch
   - Dependencies installed via `pip install -r requirements.txt`

### Using the CLI

Our `create-environment.sh` script provides a convenient way to create new environments:

```bash
# Basic usage
./scripts/create-environment.sh \
  --template dev \
  --tenant mycompany \
  --account dev \
  --environment dev-01 \
  --vpc-cidr 10.0.0.0/16

# Production with custom settings
./scripts/create-environment.sh \
  --template prod \
  --tenant mycompany \
  --account prod \
  --environment prod-01 \
  --vpc-cidr 10.0.0.0/16 \
  --region us-east-1 \
  --eks true
```

The script performs the following:

1. Validates input parameters
2. Creates directories if needed
3. Copies template files with appropriate substitution
4. Creates required certificates
5. Configures backend state
6. Updates README

### Using Atmos Workflows

Atmos workflows provide a more integrated approach for environment creation:

```bash
# Create new environment
atmos workflow onboard-environment \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  vpc_cidr=10.0.0.0/16 \
  management_account_id=123456789012

# Create from template
atmos workflow create-environment-template \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  vpc_cidr=10.0.0.0/16 \
  env_type=development
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--template`, `-t` | Template type (dev, prod, qa, data) | dev |
| `--tenant` | Tenant name (organization) | (required) |
| `--account` | AWS account name/id | (required) |
| `--environment` | Environment name | (required) |
| `--vpc-cidr` | VPC CIDR block | (required) |
| `--region` | AWS region | us-west-2 |
| `--eks` | Enable EKS cluster | true |
| `--rds` | Enable RDS database | false |
| `--monitoring` | Enable monitoring | true |
| `--flow-logs` | Enable VPC flow logs | false |
| `--secrets` | Enable Secrets Manager | true |
| `--force` | Force overwrite if environment exists | false |
| `--deploy` | Deploy after creation | false |

## Environment Workflows

Atmos provides several workflows for environment management:

### Environment Onboarding

Creates a complete environment from template and optionally deploys it.

```bash
atmos workflow onboard-environment \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  vpc_cidr=10.0.0.0/16 \
  management_account_id=123456789012
```

| Parameter | Description | Required |
|-----------|-------------|----------|
| `tenant` | Tenant name (organization) | Yes |
| `account` | AWS account name | Yes |
| `environment` | Environment name | Yes |
| `vpc_cidr` | VPC CIDR block | Yes |
| `management_account_id` | AWS management account ID | Yes |
| `region` | AWS region | No |
| `eks_enabled` | Enable EKS cluster | No |
| `deploy` | Deploy after creation | No |

The workflow performs these steps:
1. Validates parameters
2. Creates environment directories and files
3. Configures backend state
4. Sets up certificates
5. Deploys environment if requested

### Environment Creation Workflow

Creates environment files from template without deployment.

```bash
atmos workflow create-environment-template \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  vpc_cidr=10.0.0.0/16
```

| Parameter | Description | Required |
|-----------|-------------|----------|
| `tenant` | Tenant name (organization) | Yes |
| `account` | AWS account name | Yes |
| `environment` | Environment name | Yes |
| `vpc_cidr` | VPC CIDR block | Yes |
| `env_type` | Environment type | No |
| `template` | Template name | No |
| `force` | Force overwrite if environment exists | No |

### Environment Updates

Updates existing environments when templates change.

```bash
atmos workflow update-environment-template \
  tenant=mycompany \
  account=dev \
  environment=dev-01
```

| Parameter | Description | Required |
|-----------|-------------|----------|
| `tenant` | Tenant name (organization) | Yes |
| `account` | AWS account name | Yes |
| `environment` | Environment name | Yes |
| `conflict_mode` | Conflict resolution strategy | No |
| `skip_if_exists` | Skip existing files | No |
| `force` | Force update | No |

The conflict mode parameter supports several values:
- `inline` - Adds inline markers for conflicts
- `ours` - Keep our changes
- `theirs` - Use template changes
- `manual` - Stop on conflicts for manual resolution

### Environment Deployment

Deploys an environment's infrastructure.

```bash
atmos workflow apply-environment \
  tenant=mycompany \
  account=dev \
  environment=dev-01
```

| Parameter | Description | Required |
|-----------|-------------|----------|
| `tenant` | Tenant name (organization) | Yes |
| `account` | AWS account name | Yes |
| `environment` | Environment name | Yes |
| `auto_approve` | Skip confirmation | No |
| `components` | Specific components to deploy | No |
| `parallel` | Number of parallel deployments | No |

## Certificate Management

Environments require certificates for secure communication. We provide utilities for certificate management.

### Certificate Creation

To create certificates for a new environment:

```bash
# Generate certificates for a new environment
./scripts/certificates/generate-cert.sh \
  --tenant mycompany \
  --account dev \
  --environment dev-01 \
  --region us-west-2
```

This creates the following certificates:
- Environment wildcard certificate
- Service-specific certificates
- EKS cluster certificates

### Certificate Rotation

Certificates should be rotated periodically:

```bash
# Rotate certificates
atmos workflow rotate-certificate \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  certificate_name=*.dev-01.example.com
```

Or using the legacy script:

```bash
./scripts/certificates/rotate-cert.sh \
  --tenant mycompany \
  --account dev \
  --environment dev-01 \
  --certificate "*.dev-01.example.com"
```

### Integration with External Secrets

Certificates are stored in AWS Secrets Manager and accessed by applications using External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: tls-certificate
  namespace: istio-system
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: secretsmanager
    kind: ClusterSecretStore
  target:
    name: tls-certificate
    template:
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ .tls.certificate }}"
        tls.key: "{{ .tls.privateKey }}"
  data:
  - secretKey: tls
    remoteRef:
      key: "certificates/mycompany/dev/dev-01/wildcard"
```

## Environment Structure

### Directory Organization

Environments are organized in `stacks/orgs/` with a hierarchical structure:

```
stacks/orgs/
└── {tenant}/                   # Tenant (organization)
    ├── _defaults.yaml          # Tenant-wide defaults
    └── {account}/              # AWS account (dev, prod)
        ├── _defaults.yaml      # Account-wide defaults
        └── {environment}/      # Environment (region)
            ├── _defaults.yaml  # Environment defaults
            └── {region}/       # AWS region
                ├── {stage}.yaml # Stage configuration
                └── {stage}/     # Stage components
                    ├── main.yaml       # Main configuration
                    └── components/     # Component configurations
                        ├── networking.yaml
                        ├── compute.yaml
                        ├── security.yaml
                        └── services.yaml
```

### Configuration Hierarchy

Each environment imports base configurations from:

1. **Catalog components** - Base component configurations
2. **Mixins** - Environment type configurations
3. **Defaults** - Hierarchical defaults at each level

Example hierarchy (highest to lowest precedence):
1. Environment-specific configuration
2. Environment type mixin (dev, staging, prod)
3. Region mixin (us-west-2, eu-west-1)
4. Tenant mixin
5. Account defaults
6. Tenant defaults
7. Catalog defaults

### Component Structure

The `components/` directory within each environment contains configuration for infrastructure components:

```
components/
├── README.md           # Components documentation
├── compute.yaml        # Compute resources (EC2, EKS)
├── globals.yaml        # Global variables
├── networking.yaml     # VPC, subnets, routing
├── security.yaml       # IAM, security groups
└── services.yaml       # Application services
```

Each component file contains configuration for one or more Terraform components:

```yaml
# networking.yaml example
import:
  - catalog/vpc/defaults
  - mixins/region/us-west-2

components:
  terraform:
    vpc:
      vars:
        enabled: true
        name: "{{environment}}-vpc"
        cidr_block: "{{vpc_cidr}}"
        availability_zones: ["us-west-2a", "us-west-2b", "us-west-2c"]
        public_subnets_enabled: true
        private_subnets_enabled: true
        nat_gateway_enabled: true
        vpc_flow_logs_enabled: true
```

## Best Practices

### Naming Conventions

Consistent naming helps navigate and manage environments:

| Resource | Pattern | Example |
|----------|---------|---------|
| Environment | `{env-type}-{number}` | `dev-01`, `prod-02` |
| Stacks | `{tenant}-{account}-{env-name}` | `mycompany-dev-dev-01` |
| VPC | `{env-name}-vpc` | `dev-01-vpc` |
| Subnets | `{env-name}-{public/private}-{az}` | `dev-01-private-us-west-2a` |
| EKS Cluster | `{env-name}-eks` | `dev-01-eks` |
| Namespace | `{service}-{env-type}` | `api-dev`, `auth-prod` |

### CIDR Planning

1. **Avoid Overlaps**
   - Plan VPC CIDR blocks to avoid overlaps
   - Document CIDR ranges in a central location
   - Use different first/second octets for different accounts

2. **Subnet Sizing**
   - Size subnets appropriately for workload
   - Plan for growth with larger blocks where needed
   - Standard sizing:
     - Dev: /20 VPC with /24 subnets
     - Prod: /18 VPC with /22 subnets

3. **Standard Blocks**
   - Development: 10.0.0.0/16, 10.1.0.0/16
   - Staging: 10.8.0.0/16, 10.9.0.0/16
   - Production: 10.16.0.0/16 - 10.23.0.0/16
   - Shared services: 10.250.0.0/16 - 10.255.0.0/16

### Template Selection

1. **Use Case Matching**
   - Choose templates that match your use case
   - Consider performance, security, and cost requirements
   - Use the simplest template that meets requirements

2. **Customization**
   - Customize templates for specialized environments
   - Document customizations in README
   - Create new templates for frequently used customizations

3. **Versioning**
   - Use template versioning for tracking changes
   - Document template versions in environment README
   - Plan upgrades when templates change

### Security

1. **Least Privilege**
   - Use environment-appropriate security settings
   - Restrict access based on environment type
   - Use more permissive settings for dev, strict for prod

2. **Encryption**
   - Enable encryption for all sensitive data
   - Use KMS keys appropriate for the environment
   - Rotate keys according to environment policy

3. **Network Isolation**
   - Use appropriate network controls for environment type
   - More isolation for production environments
   - Control cross-environment access

### Documentation

1. **README Files**
   - Each environment should have a README
   - Document non-standard configurations
   - Include contact information for owners

2. **Diagramming**
   - Create network diagrams for each environment
   - Update diagrams when architecture changes
   - Store diagrams in version control

3. **Change Logs**
   - Document significant environment changes
   - Record template version updates
   - Note security policy changes

### Testing

1. **Validation**
   - Validate environments before deployment
   - Use `atmos workflow validate` to check configuration
   - Verify components individually before deploying all

2. **Automation Testing**
   - Test environment creation regularly
   - Create test environments for verification
   - Use CI/CD for automated testing

3. **Drift Detection**
   - Run regular drift detection checks
   - Automatically remediate drift where appropriate
   - Document manual changes

## Troubleshooting

### Common Issues

1. **Template Not Found**
   - Ensure template name is correct
   - Check that template exists in `templates/environments/`
   - Verify template file permissions

   ```bash
   # Check template directory
   ls -la templates/copier-environment/
   
   # Fix permissions if needed
   chmod -R 755 templates/copier-environment/
   ```

2. **Invalid CIDR**
   - Ensure VPC CIDR is in format `x.x.x.x/y`
   - Check for CIDR overlaps with existing environments
   - Ensure CIDR is valid for VPC (RFC 1918)

   ```bash
   # List existing environments
   atmos list stacks
   
   # Check existing VPC CIDRs
   grep -r "cidr_block" stacks/orgs/
   ```

3. **Environment Already Exists**
   - Use `--force` to overwrite
   - Specify a different environment name
   - Back up existing environment before overwriting

   ```bash
   # Backup environment
   cp -r stacks/orgs/mycompany/dev/dev-01 stacks/orgs/mycompany/dev/dev-01.bak
   
   # Use force flag
   ./scripts/create-environment.sh --force --template dev --tenant mycompany --account dev --environment dev-01
   ```

4. **Deployment Failures**
   - Check AWS credentials and permissions
   - Verify AWS account ID is correct
   - Check for resource name conflicts
   - Review CloudTrail logs for API errors

   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check component plan
   atmos terraform plan vpc -s mycompany-dev-dev-01
   ```

5. **Certificate Issues**
   - Verify certificates exist in Secrets Manager
   - Check ACM for imported certificates
   - Verify DNS validation records

   ```bash
   # List certificates in Secrets Manager
   aws secretsmanager list-secrets --filter Key=name,Values=certificates
   
   # Check ACM certificates
   aws acm list-certificates --region us-west-2
   ```

### Verification Commands

Use these commands to verify environments:

```bash
# Verify stack configuration
atmos describe stacks -s mycompany-dev-dev-01

# Verify component syntax
atmos validate component vpc -s mycompany-dev-dev-01

# Check VPC resources
aws ec2 describe-vpcs --filter "Name=tag:Name,Values=dev-01-vpc" --region us-west-2

# Verify EKS cluster
aws eks describe-cluster --name dev-01-eks --region us-west-2

# Check certificate status
aws acm describe-certificate --certificate-arn arn:aws:acm:us-west-2:123456789012:certificate/abcd1234 --region us-west-2
```

### Logging

Logs are generated during environment operations:

1. **CLI Logs**
   - Stored in `.atmos/logs/`
   - Named by date and operation

2. **Terraform Logs**
   - Set `TF_LOG=DEBUG` for detailed logs
   - Check `.terraform/` directory for state

3. **AWS CloudTrail**
   - Review CloudTrail for API errors
   - Filter by user or role used for deployment

### Getting Help

For additional help:

```bash
# CLI help
./scripts/create-environment.sh --help

# Workflow help
atmos workflow onboard-environment --help

# Check environment status
atmos describe stacks -s mycompany-dev-dev-01

# List all environments
atmos list stacks | grep mycompany
```

## Reference

### Environment Variables

#### Core Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `environment` | Environment name | `dev-01` |
| `region` | AWS region | `us-west-2` |
| `account_id` | AWS account ID | `123456789012` |
| `tenant` | Tenant/organization name | `mycompany` |
| `stage` | Deployment stage | `dev`, `prod` |

#### Component Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `vpc_azs` | Availability zones | `["us-west-2a", "us-west-2b"]` |
| `eks_version` | EKS version | `1.28` |
| `eks_node_groups` | EKS node groups | `{standard: {min_size: 2, max_size: 5}}` |
| `domain_name` | Route53 domain | `dev-01.example.com` |

### Commands Reference

#### Environment Management

| Command | Description |
|---------|-------------|
| `./scripts/create-environment.sh` | Create new environment |
| `atmos workflow onboard-environment` | Onboard new environment |
| `atmos workflow apply-environment` | Deploy environment |
| `atmos workflow plan-environment` | Plan environment changes |
| `atmos workflow destroy-environment` | Destroy environment |

#### Certificate Management

| Command | Description |
|---------|-------------|
| `./scripts/certificates/generate-cert.sh` | Generate certificate |
| `./scripts/certificates/rotate-cert.sh` | Rotate certificate |
| `./scripts/certificates/export-cert.sh` | Export certificate |
| `atmos workflow rotate-certificate` | Rotate certificate (workflow) |

#### Terraform Operations

| Command | Description |
|---------|-------------|
| `atmos terraform plan` | Plan component changes |
| `atmos terraform apply` | Apply component changes |
| `atmos terraform destroy` | Destroy component |
| `atmos terraform output` | Show component outputs |

### Related Resources

- [Terraform Development Guide](terraform-development-guide.md)
- [EKS Guide](eks-guide.md)
- [Secrets Manager Guide](secrets-manager-guide.md)
- [Certificate Management Guide](certificate-management-guide.md)
- [Security Best Practices Guide](security-best-practices-guide.md)
- [AWS Authentication Guide](aws-authentication.md)
- [Atmos Documentation](https://github.com/cloudposse/atmos)
- [Copier Documentation](https://copier.readthedocs.io/)