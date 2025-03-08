# Environment Templates Workflows

This guide covers the Atmos workflows available for working with environment templates.

## Overview

Atmos workflows provide a standardized, reproducible way to create and update environments using templates. These workflows leverage Copier for template-based environment generation with the following advantages:

- **Consistency** - All environments follow the same structure
- **Two-way Updates** - Environments can be updated when templates change
- **Validation** - Built-in validation ensures proper configuration
- **User Experience** - Interactive prompts guide users through the process

## Available Workflows

### 1. Onboard Environment

Creates a new environment with all necessary configurations and optionally deploys the infrastructure.

```bash
atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<vpc_cidr> management_account_id=<management_account_id> [region=<region>] [alarm_email=<alarm_email>]
```

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| tenant | Yes | - | Tenant/organization name |
| account | Yes | - | AWS account name (e.g., dev, prod) |
| environment | Yes | - | Environment name |
| vpc_cidr | Yes | - | VPC CIDR block (e.g., 10.0.0.0/16) |
| management_account_id | Yes | - | 12-digit AWS management account ID |
| region | No | AWS default | AWS region for resources |
| alarm_email | No | ops@example.com | Email for monitoring alerts |
| force_overwrite | No | false | Force overwrite if directory exists |
| auto_deploy | No | false | Automatically deploy the environment |

#### Examples

```bash
# Basic onboarding
atmos workflow onboard-environment tenant=mycompany account=dev environment=dev-01 vpc_cidr=10.0.0.0/16 management_account_id=123456789012

# Production environment with alerts
atmos workflow onboard-environment tenant=mycompany account=prod environment=prod-01 vpc_cidr=10.128.0.0/16 management_account_id=123456789012 region=us-east-1 alarm_email=ops-alerts@mycompany.com

# Non-interactive onboarding with automatic deployment
atmos workflow onboard-environment tenant=mycompany account=dev environment=dev-02 vpc_cidr=10.1.0.0/16 management_account_id=123456789012 auto_deploy=true force_overwrite=true
```

### 2. Create Environment Template

Creates a new environment from the Copier template.

```bash
atmos workflow create-environment-template tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<vpc_cidr> [env_type=<development|staging|production>] [region=<region>] [eks=<true|false>] [rds=<true|false>]
```

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| tenant | Yes | - | Tenant/organization name |
| account | Yes | - | AWS account name (e.g., dev, prod) |
| environment | Yes | - | Environment name (should follow pattern `name-##`) |
| vpc_cidr | Yes | - | VPC CIDR block (e.g., 10.0.0.0/16) |
| env_type | No | development | Environment type (development, staging, production) |
| region | No | AWS default | AWS region for resources |
| eks | No | true | Enable EKS cluster creation |
| rds | No | false | Enable RDS database creation |
| team_email | No | team@example.com | Team email for alerts and notifications |
| force_overwrite | No | false | Force overwrite if directory exists |
| auto_validate | No | false | Automatically validate the environment |
| auto_deploy | No | false | Automatically plan and apply the environment |

#### Examples

```bash
# Basic usage
atmos workflow create-environment-template tenant=mycompany account=dev environment=dev-01 vpc_cidr=10.0.0.0/16

# Production environment in a specific region
atmos workflow create-environment-template tenant=mycompany account=prod environment=prod-01 vpc_cidr=10.128.0.0/16 env_type=production region=us-east-1

# Development environment without EKS
atmos workflow create-environment-template tenant=mycompany account=dev environment=dev-02 vpc_cidr=10.1.0.0/16 eks=false

# QA environment with RDS
atmos workflow create-environment-template tenant=mycompany account=qa environment=qa-01 vpc_cidr=10.2.0.0/16 env_type=staging rds=true
```

### 3. Update Environment Template

Updates an existing environment with the latest template changes.

```bash
atmos workflow update-environment-template tenant=<tenant> account=<account> environment=<environment> [conflict_mode=<inline|ours|theirs>]
```

#### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| tenant | Yes | - | Tenant/organization name |
| account | Yes | - | AWS account name |
| environment | Yes | - | Environment name |
| conflict_mode | No | inline | How to handle conflicts (inline, ours, theirs) |
| auto_validate | No | false | Automatically validate after update |
| auto_plan | No | false | Automatically run plan after update |
| auto_apply | No | false | Automatically apply after plan (requires auto_plan=true) |

#### Conflict Mode Options

- **inline**: Show conflicts in the files (<<<<<<< OURS, ======= and >>>>>>> THEIRS markers)
- **ours**: Prefer existing environment's version in conflicts
- **theirs**: Prefer template's version in conflicts

#### Examples

```bash
# Basic update
atmos workflow update-environment-template tenant=mycompany account=dev environment=dev-01

# Update and prefer template changes for conflicts
atmos workflow update-environment-template tenant=mycompany account=dev environment=dev-01 conflict_mode=theirs

# Update and automatically validate and plan
atmos workflow update-environment-template tenant=mycompany account=qa environment=qa-01 auto_validate=true auto_plan=true
```

## Workflow Process

### Create Environment Template Workflow

1. **Validation** - Validates input parameters
2. **Configuration** - Sets up environment based on parameters
3. **Template Generation** - Runs Copier to create the environment from template
4. **Validation** - Offers to validate the generated configuration
5. **Deployment** - Offers to plan and apply the environment

### Onboard Environment Workflow

1. **Validation** - Validates input parameters and management account ID
2. **Environment Type** - Determines environment type based on account name
3. **Template Generation** - Uses Copier to create the environment from template
4. **Backend Configuration** - Adds backend configuration for Terraform state
5. **IAM Configuration** - Adds IAM configuration for cross-account access
6. **Validation** - Validates the environment configuration
7. **Deployment** - Offers to apply the environment infrastructure

### Update Environment Template Workflow

1. **Validation** - Checks that the environment exists and was created with Copier
2. **Update** - Runs Copier update to apply template changes
3. **Preview** - Shows the changes that were made
4. **Validation** - Offers to validate the updated configuration
5. **Deployment** - Offers to plan and apply the updated environment

## Template Organization

The templates are stored in the `/templates/copier-environment` directory with the following structure:

```
templates/copier-environment/
├── copier.yml                # Template configuration
├── README.md                 # Template documentation
├── {{env_name}}/             # Environment template files
│   ├── README.md             # Environment documentation
│   └── stacks/
│       └── {{tenant}}/
│           └── {{account}}/
│               └── {{env_name}}/
│                   ├── main.yaml       # Main configuration
│                   ├── variables.yaml  # Environment variables
│                   ├── networking.yaml # Network configuration
│                   └── eks.yaml        # EKS configuration (conditional)
└── hooks/                   # Pre/post generation scripts
    ├── post_gen.py          # Post-generation processing
    └── pre_gen.py           # Pre-generation validation
```

## Best Practices

1. **Naming Convention** - Use consistent naming patterns (`name-##`) for environments
2. **Template Updates** - Update templates consistently across all environments
3. **Environment Types** - Use appropriate environment types for different tiers
   - `development` - For dev/test with minimal resources
   - `staging` - For pre-production with moderate resources
   - `production` - For production with high availability
4. **Validation** - Always validate after creating or updating environments
5. **CIDR Planning** - Plan VPC CIDR blocks carefully for future expansion
6. **Git Integration** - Commit environment configurations after creating or updating