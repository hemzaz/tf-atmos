# Atmos Workflows

This directory contains comprehensive Atmos workflow definitions for infrastructure operations. These workflows provide standardized, reliable, and secure processes for managing Terraform infrastructure at scale.

## 🏗️ Architecture Overview

All workflows follow a consistent multi-step architecture:
1. **Input Validation** - Validate parameters and environment setup
2. **Pre-execution Checks** - Verify prerequisites and dependencies  
3. **Core Operations** - Execute the primary workflow logic
4. **Post-execution Validation** - Verify results and state consistency
5. **Summary & Guidance** - Provide actionable results and next steps

## 📋 Available Workflows

### Core Infrastructure Operations

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **lint** | Code quality and security scanning | `atmos workflow lint -f lint.yaml [fix=true] [skip_security=true]` |
| **validate** | Component validation for a stack | `atmos workflow validate -f validate.yaml tenant=<tenant> account=<account> environment=<environment>` |
| **plan-environment** | Generate execution plans | `atmos workflow plan-environment -f plan-environment.yaml tenant=<tenant> account=<account> environment=<environment>` |
| **apply-environment** | Apply infrastructure changes | `atmos workflow apply-environment -f apply-environment.yaml tenant=<tenant> account=<account> environment=<environment> [auto_approve=true]` |
| **drift-detection** | Detect configuration drift | `atmos workflow drift-detection -f drift-detection.yaml tenant=<tenant> account=<account> environment=<environment>` |

### Resource Management

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **import** | Import existing AWS resources | `atmos workflow import -f import.yaml tenant=<tenant> account=<account> environment=<environment> component=<component> resource_address=<address> resource_id=<id>` |
| **destroy-environment** | Safely destroy infrastructure | `atmos workflow destroy-environment -f destroy-environment.yaml tenant=<tenant> account=<account> environment=<environment> [auto_approve=true]` |

### Backend Operations

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **bootstrap-backend** | Initialize Terraform backend | `atmos workflow bootstrap-backend -f bootstrap-backend.yaml tenant=<tenant> region=<region>` |
| **apply-backend** | Manage backend infrastructure | `atmos workflow apply-backend -f apply-backend.yaml tenant=<tenant> region=<region>` |
| **destroy-backend** | Remove backend infrastructure | `atmos workflow destroy-backend -f destroy-backend.yaml tenant=<tenant> region=<region>` |

### Environment Management

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **onboard-environment** | Create new environments | `atmos workflow onboard-environment -f onboard-environment.yaml tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr>` |
| **create-environment-template** | Generate from templates | `atmos workflow create-environment-template -f create-environment-template.yaml tenant=<tenant> account=<account> environment=<environment>` |
| **update-environment-template** | Update template-based envs | `atmos workflow update-environment-template -f update-environment-template.yaml tenant=<tenant> account=<account> environment=<environment>` |

### Security & Compliance

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **compliance-check** | Security and compliance validation | `atmos workflow compliance-check -f compliance-check.yaml tenant=<tenant> account=<account> environment=<environment>` |
| **rotate-certificate** | Certificate rotation management | `atmos workflow rotate-certificate -f rotate-certificate.yaml secret_name=<secret> namespace=<namespace>` |

### Operations & Maintenance

| Workflow | Purpose | Usage |
|----------|---------|-------|
| **state-operations** | Terraform state management | `atmos workflow state-operations -f state-operations.yaml action=<list\|detect\|clean> tenant=<tenant> account=<account> environment=<environment>` |

## 🚀 Quick Start Examples

### 1. Validate Infrastructure
```bash
# Run linting and validation
atmos workflow lint -f lint.yaml fix=true
atmos workflow validate -f validate.yaml tenant=fnx account=dev environment=testenv-01
```

### 2. Plan and Apply Changes
```bash
# Generate execution plans
atmos workflow plan-environment -f plan-environment.yaml \
  tenant=fnx account=dev environment=testenv-01 \
  output_dir=./plans/dev-review

# Apply changes (with confirmation)
atmos workflow apply-environment -f apply-environment.yaml \
  tenant=fnx account=dev environment=testenv-01 \
  auto_approve=false

# Apply changes (auto-approve for CI/CD)
atmos workflow apply-environment -f apply-environment.yaml \
  tenant=fnx account=dev environment=testenv-01 \
  auto_approve=true
```

### 3. Drift Detection and Remediation
```bash
# Detect drift
atmos workflow drift-detection -f drift-detection.yaml \
  tenant=fnx account=prod environment=main

# Review and fix drift
atmos workflow plan-environment -f plan-environment.yaml \
  tenant=fnx account=prod environment=main
```

### 4. Import Existing Resources
```bash
# Import an S3 bucket
atmos workflow import -f import.yaml \
  tenant=fnx account=dev environment=testenv-01 \
  component=s3-bucket \
  resource_address=aws_s3_bucket.main \
  resource_id=my-existing-bucket-name
```

## ⚙️ Parameters Reference

### Common Parameters
- **tenant** - Organization identifier (e.g., "fnx", "acme")
- **account** - Account identifier (e.g., "dev", "prod", "staging")  
- **environment** - Environment name (e.g., "testenv-01", "main")
- **parallel** - Enable parallel execution (true/false, default: false)

### Security Parameters
- **auto_approve** - Skip manual confirmation (true/false, default: false)
- **force_import** - Force re-import of existing resources (true/false)
- **skip_security** - Skip security scanning (true/false, default: false)

### Output Parameters
- **output_dir** - Directory for plan outputs (default: auto-generated)
- **report_format** - Report format for drift detection (json/text/both)

## 🔐 Security Best Practices

### Input Validation
- All workflows validate required parameters before execution
- AWS credentials are verified before any operations
- Stack and component existence is confirmed

### Safe Operations
- **Plan-first approach**: Generate plans before applying changes
- **Drift detection**: Regular drift monitoring with detailed reporting
- **State protection**: Safe state operations with backup validation
- **Resource validation**: Pre and post-operation validation checks

### Access Control
- Workflows respect AWS IAM permissions
- Stack-level isolation prevents cross-environment impact
- Component-level granular control

## 📊 Workflow States and Exit Codes

### Standard Exit Codes
- **0**: Success - operation completed successfully
- **1**: Error - operation failed with recoverable error
- **2**: Warning - operation completed with warnings (e.g., drift detected)

### Common Workflow States
- **Input Validation**: Parameter and environment checks
- **Pre-execution**: Prerequisites and dependency validation
- **Core Operation**: Main workflow logic execution
- **Post-validation**: Result verification and state consistency
- **Summary**: Results reporting and next step guidance

## 🔍 Monitoring and Observability

### Logging
- Structured logging with timestamps and operation context
- Detailed step-by-step execution tracking
- Error context and remediation guidance

### Reporting
- JSON and human-readable reports for all operations
- Drift detection with detailed change analysis
- Plan summaries with resource impact assessment

### Troubleshooting
- Comprehensive error messages with resolution steps
- Common failure scenarios with specific guidance
- Resource state validation and recovery procedures

## 🛠️ Advanced Usage

### CI/CD Integration
```bash
# Pipeline-friendly execution with proper exit codes
set -e
atmos workflow lint -f lint.yaml fix=false
atmos workflow validate -f validate.yaml tenant=fnx account=dev environment=ci
atmos workflow plan-environment -f plan-environment.yaml tenant=fnx account=dev environment=ci
atmos workflow apply-environment -f apply-environment.yaml tenant=fnx account=dev environment=ci auto_approve=true
```

### Batch Operations
```bash
# Multiple environment operations
for env in dev staging prod; do
  echo "Processing environment: $env"
  atmos workflow drift-detection -f drift-detection.yaml \
    tenant=fnx account=main environment=$env
done
```

### Custom Workflows
See individual workflow files for advanced parameters and customization options. Each workflow is designed to be:
- **Composable**: Can be combined with other workflows
- **Extensible**: Supports custom parameters and configurations  
- **Reliable**: Comprehensive error handling and validation
- **Observable**: Detailed logging and reporting

## 📞 Support and Troubleshooting

### Common Issues
1. **AWS Credentials**: Ensure valid credentials with appropriate permissions
2. **Stack Configuration**: Verify stack exists in Atmos configuration
3. **Component Validation**: Fix component configuration before operations
4. **State Locks**: Handle DynamoDB state locks appropriately

### Getting Help
- Review workflow-specific documentation in individual YAML files
- Check execution logs for detailed error context
- Validate prerequisites using the validation workflow
- Use drift-detection to understand current state vs. configuration

---

*Last Updated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')*