# Jenkins Integration for Atmos

_Last Updated: February 28, 2025_

This directory contains the configuration needed to integrate Jenkins with Atmos for automated Terraform workflow execution.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Usage](#usage)
- [Security Considerations](#security-considerations)
- [Error Handling](#error-handling)
- [Cross-Account Authentication](#cross-account-authentication)
- [Troubleshooting](#troubleshooting)
- [Customization](#customization)
- [Version Compatibility](#version-compatibility)
- [Related Resources](#related-resources)

## Overview

The Atmos Jenkins integration provides automated infrastructure deployment pipelines that enforce consistent workflows across all environments. It supports Atmos's multi-account architecture with robust error handling, validation checks, and production safeguards.

## Features

- Automated pipeline for running Atmos workflows
- Supports all Atmos commands (plan, apply, destroy)
- Multi-environment support via tenant/account/environment model
- Component-specific targeting capabilities
- Pre-flight checks with linting and validation
- Repository structure auto-detection
- Robust error handling with retry logic
- Cross-account authentication support
- Production environment approval gates
- Post-apply validation tests
- Plan artifact storage for audit trails

## Architecture

The integration uses a containerized approach with the following components:

1. **Jenkins Pipeline**: Orchestrates the workflow with stages for validation, planning, approval, and application
2. **Atmos Container**: Provides a consistent execution environment with all dependencies
3. **AWS Authentication**: Uses role assumption for secure cross-account access
4. **Validation Layer**: Ensures code quality and detects potential issues before deployment
5. **Approval Mechanism**: Requires manual intervention for production environments

## Setup Instructions

### Prerequisites

1. Jenkins server 2.375.1 or later with Docker support
2. AWS credentials properly configured for Jenkins
3. Network access to AWS services
4. Git repository containing Atmos configuration

### Installation

1. Add the Jenkinsfile to your Atmos repository
2. Create a new Jenkins Pipeline job pointing to your repository
3. Configure AWS credential parameters:
   - For each account, create a credential named `{account-name}-role-arn` containing the role ARN
   - Set up IAM roles in each AWS account with appropriate permissions
4. Configure webhook triggers from your Git provider (optional)

### Required Jenkins Plugins

- Pipeline (2.6 or later)
- Docker Pipeline (1.29 or later)
- Git Integration (5.0 or later)
- Credentials Binding (523.v439f80869e3c or later)
- Pipeline: AWS Steps (1.56 or later)

## Usage

### Running the Pipeline

The pipeline can be triggered manually with the following parameters:

| Parameter | Description | Example Values |
|-----------|-------------|----------------|
| TENANT | The organizational tenant name | `acme`, `organization` |
| ACCOUNT | The AWS account name | `dev`, `staging`, `prod` |
| ENVIRONMENT | The environment name | `us-east-1`, `us-west-2` |
| ACTION | The Terraform action to perform | `plan`, `apply`, `destroy` |
| COMPONENT | Specific component to target (optional) | `vpc`, `eks`, `rds` |
| REQUIRE_APPROVAL | Whether to require approval (default: true) | `true`, `false` |
| AWS_ROLE_SESSION_NAME | Session name for cross-account access | `atmos-jenkins-automation` |

### Examples

#### Planning Changes for an Entire Environment

This will run a plan for all components in the specified environment:

```
TENANT: acme
ACCOUNT: dev
ENVIRONMENT: us-east-1
ACTION: plan
COMPONENT: (leave empty)
REQUIRE_APPROVAL: true
AWS_ROLE_SESSION_NAME: atmos-jenkins-dev
```

#### Applying a Single Component

This will apply changes only for the specified component:

```
TENANT: acme
ACCOUNT: prod
ENVIRONMENT: us-west-2
ACTION: apply
COMPONENT: vpc
REQUIRE_APPROVAL: true
AWS_ROLE_SESSION_NAME: atmos-jenkins-prod
```

## Security Considerations

- The pipeline uses the cloudposse/atmos-terraform Docker image for isolation
- AWS credentials are securely managed using role assumption
- Production environments require explicit approval before applying changes
- No sensitive values are exposed in logs
- Workspace is cleaned after each run
- Cross-account access uses temporary credentials with limited permissions
- Plan files are archived for audit trail purposes

## Error Handling

The pipeline includes comprehensive error handling:

- Retry logic for transient failures
- Descriptive error messages for troubleshooting
- Validation of repository structure before execution
- Graceful failure with detailed logging
- Post-apply validation to detect drift or configuration issues

## Cross-Account Authentication

For multi-account deployments, the integration:

1. Detects the account from the stack name
2. Looks up the appropriate role ARN from Jenkins credentials
3. Assumes the role with the specified session name
4. Verifies permissions before attempting operations
5. Cleans up temporary credentials after use

## Troubleshooting

### Common Issues

1. **AWS credential issues**: 
   - Error: "Unable to locate credentials"
   - Solution: Ensure role ARN credentials are properly configured in Jenkins

2. **Missing Atmos configuration**: 
   - Error: "Could not detect Atmos repository structure"
   - Solution: Verify atmos.yaml exists at the root of your repository

3. **Component not found**: 
   - Error: "Component X not found in repository"
   - Solution: Check that the component exists in ./components/terraform/

4. **Stack not found**:
   - Error: "Stack X not found in repository"
   - Solution: Verify stack configuration exists in ./stacks/

### Logs and Debugging

Pipeline logs can be viewed in the Jenkins UI. For detailed debugging:

1. Enable verbose mode by adding `-v` to the Atmos commands in the Jenkinsfile
2. Examine the archived plan files for detailed change information
3. Check workspace contents before cleanup by commenting out the `cleanWs()` command
4. Add debug echo statements to the pipeline for variable inspection
5. Look for specific error messages in the "Setup" and "Repository Structure Detection" stages

## Customization

The Jenkinsfile can be customized for your specific needs:

- Add additional stages for testing or security scanning
- Modify the Docker image version or use a custom image
- Adjust retry settings and timeout periods
- Add notification integrations (Slack, email, etc.)
- Implement custom validation steps
- Add environment-specific logic

## Version Compatibility

This integration has been tested with:

- Atmos v1.44.0 or later
- Terraform v1.5.0 or later
- AWS Provider v4.9.0 or later
- Jenkins v2.375.1 or later

## Related Resources

- [Atmos Documentation](https://atmos.tools/)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [AWS Assume Role Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [CI/CD Best Practices Guide](../docs/cicd-best-practices.md)
- [AWS Authentication Guide](../docs/aws-authentication.md)