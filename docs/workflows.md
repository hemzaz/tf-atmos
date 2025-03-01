# Atmos Workflows Guide

_Last Updated: February 28, 2025_

This guide provides comprehensive documentation on using, customizing, and extending workflows in the Atmos framework to automate and standardize infrastructure operations.

## Table of Contents

- [Introduction](#introduction)
- [Standard Workflows](#standard-workflows)
- [Workflow Architecture](#workflow-architecture)
- [Using Workflows](#using-workflows)
- [Customizing Workflows](#customizing-workflows)
- [Creating New Workflows](#creating-new-workflows)
- [CI/CD Integration](#cicd-integration)
- [Advanced Patterns](#advanced-patterns)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

## Introduction

Atmos workflows are predefined sequences of commands that automate common infrastructure operations. They provide:

- **Standardization** - Consistent processes across environments
- **Automation** - Reduced manual operations and human error
- **Documentation** - Self-documenting infrastructure operations
- **Guardrails** - Built-in validations and approvals
- **Flexibility** - Customizable to specific organizational needs

Workflows are defined in YAML files in the `workflows/` directory and can be executed using the `atmos workflow` command.

## Standard Workflows

The following standard workflows are included:

### Environment Management

| Workflow | Description | Usage |
|----------|-------------|-------|
| `bootstrap-backend` | Initialize backend infrastructure with enhanced security | `atmos workflow bootstrap-backend tenant=mycompany region=us-west-2 [bucket_suffix=custom-suffix]` |
| `apply-backend` | Apply backend configuration | `atmos workflow apply-backend tenant=mycompany account=management environment=prod` |
| `onboard-environment` | Create new environment | `atmos workflow onboard-environment tenant=mycompany account=dev environment=testenv-01 vpc_cidr=10.1.0.0/16 management_account_id=123456789012 [auto_deploy=true] [force_overwrite=true]` |
| `apply-environment` | Apply all components with auto-discovery | `atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01` |
| `plan-environment` | Plan all components with auto-discovery | `atmos workflow plan-environment tenant=mycompany account=dev environment=testenv-01` |
| `destroy-environment` | Destroy all components | `atmos workflow destroy-environment tenant=mycompany account=dev environment=testenv-01` |

### Operations

| Workflow | Description | Usage |
|----------|-------------|-------|
| `drift-detection` | Detect infrastructure drift with detailed reporting | `atmos workflow drift-detection tenant=mycompany account=dev environment=testenv-01` |
| `import` | Import existing resources | `atmos workflow import tenant=mycompany account=dev environment=testenv-01` |
| `validate` | Validate configuration with component auto-discovery | `atmos workflow validate tenant=mycompany account=dev environment=testenv-01` |
| `lint` | Comprehensive linting with support for multiple tools | `atmos workflow lint` |

## Workflow Architecture

Workflows are defined in YAML files with the following structure:

```yaml
name: workflow-name
description: "Workflow description"
args:
  - name: arg1
    description: "Argument description"
    required: true
  - name: arg2
    description: "Argument description"
    required: false
    default: "default-value"
steps:
  - name: step1
    description: "Step description"
    command: command-to-execute
    args:
      - arg1
      - arg2
    interactive: false  # Whether step requires user interaction
  - name: step2
    description: "Step description"
    command: command-to-execute
    args:
      - arg1
      - "{arg2}"  # Reference to workflow argument
```

### Key Components

- **name** - Unique workflow identifier
- **description** - Human-readable workflow description
- **args** - Arguments required or optional for the workflow
- **steps** - Sequence of commands to execute
- **command** - Command to execute for each step
- **args** - Arguments for the command
- **interactive** - Whether the step requires user interaction

## Using Workflows

### Basic Usage

To execute a workflow:

```bash
atmos workflow <workflow-name> [args]
```

Example:

```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
```

### Workflow Argument Handling

Arguments can be provided in key=value format:

```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
```

Or using environment variables:

```bash
export ATMOS_TENANT=mycompany
export ATMOS_ACCOUNT=dev
export ATMOS_ENVIRONMENT=testenv-01
atmos workflow apply-environment
```

### Interactive Workflows

Some workflows may include interactive steps that require user input:

```yaml
steps:
  - name: confirm-deploy
    description: "Confirm deployment to production"
    command: read
    args:
      - -p
      - "Do you want to deploy to production? (y/n): "
    interactive: true
```

### Viewing Available Workflows

List all available workflows:

```bash
atmos workflow list
```

View details about a specific workflow:

```bash
atmos workflow describe <workflow-name>
```

## Customizing Workflows

### Modifying Existing Workflows

To customize an existing workflow:

1. Copy the workflow file to a new file
2. Modify the workflow as needed
3. Change the workflow name to avoid conflicts

Example:

```bash
cp workflows/apply-environment.yaml workflows/apply-environment-with-approval.yaml
# Edit the new file
```

### Extending Workflows

Add additional steps to existing workflows:

```yaml
# workflows/apply-environment-extended.yaml
name: apply-environment-extended
description: "Apply environment with additional steps"
args:
  # Same args as original workflow
steps:
  # Original steps from apply-environment
  # Additional steps:
  - name: notify-slack
    description: "Notify Slack channel"
    command: bash
    args:
      - -c
      - "curl -X POST -H 'Content-type: application/json' --data '{\"text\":\"Environment {environment} deployed\"}' $SLACK_WEBHOOK_URL"
```

### Environment-Specific Workflows

Create environment-specific workflows:

```yaml
# workflows/apply-production.yaml
name: apply-production
description: "Apply changes to production with approvals"
args:
  - name: tenant
    required: true
steps:
  - name: get-approval
    description: "Get approval for production deployment"
    command: bash
    args:
      - -c
      - "echo 'Production deployment requires approval' && read -p 'Enter approval code: ' code && [ \"$code\" == \"$PROD_APPROVAL_CODE\" ]"
    interactive: true
  
  # Call standard apply-environment workflow
  - name: apply
    description: "Apply environment"
    command: atmos
    args:
      - workflow
      - apply-environment
      - tenant={tenant}
      - account=prod
      - environment=us-east-1
```

## Creating New Workflows

### Basic Workflow Structure

Create a new workflow file:

```yaml
# workflows/my-workflow.yaml
name: my-workflow
description: "Custom workflow description"
args:
  - name: tenant
    description: "Tenant name"
    required: true
  - name: component
    description: "Component to deploy"
    required: true
steps:
  - name: validate
    description: "Validate component"
    command: atmos
    args:
      - terraform
      - validate
      - "{component}"
      - -s
      - "{tenant}-dev-us-east-1"
  
  - name: plan
    description: "Plan component"
    command: atmos
    args:
      - terraform
      - plan
      - "{component}"
      - -s
      - "{tenant}-dev-us-east-1"
  
  - name: apply
    description: "Apply component"
    command: atmos
    args:
      - terraform
      - apply
      - "{component}"
      - -s
      - "{tenant}-dev-us-east-1"
      - --auto-approve
```

### Advanced Workflow Features

#### Conditional Execution

Use Bash conditionals for conditional execution:

```yaml
steps:
  - name: check-environment
    description: "Check if production environment"
    command: bash
    args:
      - -c
      - |
        if [ "{environment}" == "prod" ]; then
          echo "Production environment detected"
          exit 0
        else
          echo "Non-production environment, skipping approval"
          exit 1
        fi
    interactive: false
    
  - name: production-approval
    description: "Get approval for production"
    condition: "check-environment"  # Only execute if previous step exits with 0
    command: bash
    args:
      - -c
      - "read -p 'Enter approval code: ' code && [ \"$code\" == \"$APPROVAL_CODE\" ]"
    interactive: true
```

#### Environment Variables

Pass environment variables to workflow steps:

```yaml
steps:
  - name: deploy-with-vars
    description: "Deploy with environment variables"
    command: bash
    args:
      - -c
      - "AWS_PROFILE={tenant}-{account} terraform apply -auto-approve"
    env:
      - name: TF_VAR_environment
        value: "{environment}"
      - name: TF_VAR_region
        value: "{region}"
```

#### Error Handling

Add error handling to workflows:

```yaml
steps:
  - name: risky-operation
    description: "Operation that might fail"
    command: bash
    args:
      - -c
      - "command_that_might_fail || (echo 'Operation failed, running cleanup' && cleanup_command)"
    on_error:
      command: bash
      args:
        - -c
        - "echo 'Error occurred, running recovery' && recovery_command"
```

## CI/CD Integration

### GitHub Actions Integration

```yaml
# .github/workflows/atmos-deploy.yml
name: Deploy with Atmos

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        
      - name: Install Atmos
        run: |
          curl -s https://raw.githubusercontent.com/cloudposse/atmos/master/scripts/install.sh | bash
          
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
          
      - name: Run Atmos Workflow
        run: |
          atmos workflow plan-environment tenant=mycompany account=dev environment=testenv-01
```

### GitLab CI Integration

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - plan
  - apply

variables:
  TENANT: mycompany
  ACCOUNT: dev
  ENVIRONMENT: testenv-01

# Install dependencies
.install_deps: &install_deps
  before_script:
    # Install dependencies from .env file
    - |
      #!/usr/bin/env bash
      # Create .env file with versions if needed
      if [ ! -f .env ]; then
        cat > .env << EOF
        TERRAFORM_VERSION="1.5.7"
        ATMOS_VERSION="1.38.0"
        KUBECTL_VERSION="1.28.3"
        HELM_VERSION="3.13.1"
        EOF
      fi
      
      # Run installation script
      ./scripts/install-dependencies.sh
    
    # Install additional dependencies
    - apt-get update && apt-get install -y yamllint jq
    
validate:
  stage: validate
  <<: *install_deps
  script:
    - atmos workflow validate tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT
    - atmos workflow lint

plan:
  stage: plan
  <<: *install_deps
  script:
    - atmos workflow plan-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT
  artifacts:
    paths:
      - plan.tfplan

apply:
  stage: apply
  <<: *install_deps
  script:
    # Use auto_deploy=true for non-interactive environments
    - atmos workflow apply-environment tenant=$TENANT account=$ACCOUNT environment=$ENVIRONMENT
  when: manual
  only:
    - main
```

### Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent {
        // Use a Jenkins agent with needed tools
        docker {
            image 'hashicorp/terraform:latest'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    
    parameters {
        string(name: 'TENANT', defaultValue: 'mycompany')
        string(name: 'ACCOUNT', defaultValue: 'dev')
        string(name: 'ENVIRONMENT', defaultValue: 'testenv-01')
        // Optional parameters
        booleanParam(name: 'AUTO_DEPLOY', defaultValue: false, description: 'Automatically deploy after planning')
        booleanParam(name: 'FORCE_OVERWRITE', defaultValue: false, description: 'Force overwrite existing configurations')
    }
    
    environment {
        // Pass environment variables to workflows
        AUTO_DEPLOY = "${params.AUTO_DEPLOY}"
        FORCE_OVERWRITE = "${params.FORCE_OVERWRITE}"
    }
    
    stages {
        stage('Install Dependencies') {
            steps {
                // Install Atmos and dependencies
                sh '''
                    #!/usr/bin/env bash
                    # Create .env file with tool versions if needed
                    if [ ! -f .env ]; then
                        cat > .env << 'EOF'
                        TERRAFORM_VERSION="1.5.7"
                        ATMOS_VERSION="1.38.0"
                        KUBECTL_VERSION="1.28.3"
                        HELM_VERSION="3.13.1"
                        EOF
                    fi
                    
                    # Run installation script which handles cross-platform installation
                    ./scripts/install-dependencies.sh
                    
                    # Install additional tools
                    apt-get update && apt-get install -y jq yamllint curl
                    
                    # Set the PATH to include the required binaries
                    export PATH=$PATH:$HOME/.atmos/bin
                '''
            }
        }
        
        stage('Validate') {
            steps {
                sh "atmos workflow validate tenant=${params.TENANT} account=${params.ACCOUNT} environment=${params.ENVIRONMENT}"
                sh "atmos workflow lint"
            }
        }
        
        stage('Plan') {
            steps {
                sh "atmos workflow plan-environment tenant=${params.TENANT} account=${params.ACCOUNT} environment=${params.ENVIRONMENT}"
            }
        }
        
        stage('Apply') {
            when {
                anyOf {
                    expression { return params.AUTO_DEPLOY }
                    expression { return env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master' }
                }
            }
            steps {
                input message: 'Apply changes?', ok: 'Apply'
                sh "atmos workflow apply-environment tenant=${params.TENANT} account=${params.ACCOUNT} environment=${params.ENVIRONMENT} auto_deploy=true"
            }
        }
    }
    
    post {
        always {
            // Archive Terraform plans and logs
            archiveArtifacts artifacts: '**/plan.out, **/terraform.log', allowEmptyArchive: true
        }
    }
}
```

## Advanced Patterns

### Multi-Environment Deployments

Deploy to multiple environments sequentially:

```yaml
# workflows/deploy-all-environments.yaml
name: deploy-all-environments
description: "Deploy to all environments sequentially"
args:
  - name: tenant
    required: true
steps:
  - name: deploy-dev
    description: "Deploy to development"
    command: atmos
    args:
      - workflow
      - apply-environment
      - tenant={tenant}
      - account=dev
      - environment=testenv-01
      
  - name: deploy-staging
    description: "Deploy to staging"
    command: atmos
    args:
      - workflow
      - apply-environment
      - tenant={tenant}
      - account=staging
      - environment=us-east-1
    
  - name: approve-production
    description: "Approve production deployment"
    command: bash
    args:
      - -c
      - "read -p 'Deploy to production? (y/n): ' approval && [ \"$approval\" == \"y\" ]"
    interactive: true
    
  - name: deploy-production
    description: "Deploy to production"
    command: atmos
    args:
      - workflow
      - apply-environment
      - tenant={tenant}
      - account=prod
      - environment=us-east-1
```

### Rolling Back Deployments

Create workflows for safe rollbacks:

```yaml
# workflows/rollback-environment.yaml
name: rollback-environment
description: "Rollback environment to previous state"
args:
  - name: tenant
    required: true
  - name: account
    required: true
  - name: environment
    required: true
  - name: version
    description: "Version to rollback to"
    required: true
steps:
  - name: fetch-state
    description: "Fetch previous state version"
    command: bash
    args:
      - -c
      - |
        aws s3 cp s3://{tenant}-terraform-state/{account}/{environment}/terraform.tfstate.{version} \
          s3://{tenant}-terraform-state/{account}/{environment}/terraform.tfstate
  
  - name: apply-environment
    description: "Apply environment with previous state"
    command: atmos
    args:
      - workflow
      - apply-environment
      - tenant={tenant}
      - account={account}
      - environment={environment}
```

### Custom Approval Workflows

Implement custom approval mechanisms:

```yaml
# workflows/approve-changes.yaml
name: approve-changes
description: "Approve changes with multi-person approval"
args:
  - name: tenant
    required: true
  - name: account
    required: true
  - name: environment
    required: true
steps:
  - name: generate-plan
    description: "Generate Terraform plan"
    command: atmos
    args:
      - workflow
      - plan-environment
      - tenant={tenant}
      - account={account}
      - environment={environment}
      - --tf-plan-file=changes.plan
  
  - name: upload-plan
    description: "Upload plan for review"
    command: bash
    args:
      - -c
      - "aws s3 cp changes.plan s3://{tenant}-approvals/{account}-{environment}-$(date +%Y%m%d%H%M%S).plan"
  
  - name: notify-approvers
    description: "Notify approvers"
    command: bash
    args:
      - -c
      - "curl -X POST -H 'Content-type: application/json' --data '{\"text\":\"Changes ready for approval: {account}/{environment}\"}' $SLACK_WEBHOOK_URL"
  
  - name: wait-for-approval
    description: "Wait for approval"
    command: bash
    args:
      - -c
      - "while [ ! -f approval.txt ]; do echo 'Waiting for approval...'; sleep 60; done"
    interactive: true
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Workflow not found | Incorrect workflow name or path | Check workflow name and `workflows/` directory |
| Missing arguments | Required arguments not provided | Provide all required arguments |
| Command execution failure | Command returns non-zero exit code | Check command output and fix errors |
| Interactive step hangs in CI | Interactive step in non-interactive environment | Set `interactive: false` or use `auto_deploy=true` |
| Permission denied | Insufficient permissions | Check AWS credentials and IAM roles |
| Component dependencies | Components deployed in wrong order | The workflows now use automatic dependency detection based on imports and output references |
| Region-specific errors | Issues with specific AWS regions | Check region compatibility and validation |

### CI/CD-Specific Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Non-interactive prompts | CI environment can't handle prompts | Use `auto_deploy=true` and `force_overwrite=true` parameters |
| Missing dependencies | Required tools not installed | Install yamllint, jq, and other dependencies in CI |
| Path issues | Atmos not in PATH | Export PATH to include Atmos binary location |
| Permission denied on clipboard | CI doesn't have clipboard access | This is expected in CI; output is shown in logs instead |
| Missing AWS credentials | Credentials not configured | Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables |

### Debugging Workflows

Enable verbose output to debug workflow execution:

```bash
atmos --verbose workflow <workflow-name> [args]
```

Check workflow logs:

```bash
atmos logs
```

Debug component discovery:

```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01 --debug
```

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `Workflow '<n>' not found` | Workflow file missing or incorrectly named | Check workflow file exists in `workflows/` directory |
| `Missing required argument '<arg>'` | Required argument not provided | Provide the required argument |
| `Command '<command>' not found` | Command doesn't exist or isn't in PATH | Install missing command or correct path |
| `Step '<step>' failed with exit code <code>` | Command execution failed | Check command output and fix errors |
| `Directory does not exist` | Environment directory not found | Check path and create directory structure |
| `No components found` | No YAML files in environment directory | Create component YAML files first |
| `DRIFT DETECTED` | Infrastructure drift detected | Review and reconcile differences |
| `Terraform plan failed` | Issues with Terraform configuration | Check Terraform code for errors |

## Reference

### Workflow YAML Reference

| Field | Description | Required | Example |
|-------|-------------|----------|---------|
| `name` | Workflow name | Yes | `apply-environment` |
| `description` | Workflow description | Yes | `"Apply all components in an environment"` |
| `args` | Workflow arguments | No | See below |
| `args[].name` | Argument name | Yes | `tenant` |
| `args[].description` | Argument description | Yes | `"Tenant name"` |
| `args[].required` | Whether argument is required | Yes | `true` |
| `args[].default` | Default value if not provided | No | `"default-value"` |
| `steps` | Workflow steps | Yes | See below |
| `steps[].name` | Step name | Yes | `apply-vpc` |
| `steps[].description` | Step description | Yes | `"Apply VPC component"` |
| `steps[].command` | Command to execute | Yes | `atmos` |
| `steps[].args` | Command arguments | Yes | `["terraform", "apply", "vpc"]` |
| `steps[].interactive` | Whether step requires interaction | No | `false` |
| `steps[].condition` | Step to condition execution on | No | `check-environment` |
| `steps[].env` | Environment variables for the step | No | See below |
| `steps[].env[].name` | Environment variable name | Yes | `TF_VAR_region` |
| `steps[].env[].value` | Environment variable value | Yes | `"{region}"` |

### Argument Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{tenant}` | Tenant name | `mycompany` |
| `{account}` | Account name | `dev` |
| `{environment}` | Environment name | `testenv-01` |
| `{region}` | AWS region | `us-east-1` |
| `{component}` | Component name | `vpc` |

### Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| `atmos workflow list` | List available workflows | `atmos workflow list` |
| `atmos workflow describe <n>` | Describe workflow | `atmos workflow describe apply-environment` |
| `atmos workflow <n> [args]` | Execute workflow | `atmos workflow apply-environment tenant=mycompany` |
| `atmos workflow edit <n>` | Edit workflow (if editor configured) | `atmos workflow edit apply-environment` |