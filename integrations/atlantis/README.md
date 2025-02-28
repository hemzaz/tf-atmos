# Atlantis Integration for Atmos

_Last Updated: February 28, 2025_

This directory contains the configuration needed to integrate Atlantis with Atmos for automated Terraform workflow execution and pull request automation.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Configuration](#configuration)
- [Usage](#usage)
- [Security Considerations](#security-considerations)
- [Multi-Account Management](#multi-account-management)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Version Compatibility](#version-compatibility)
- [Additional Resources](#additional-resources)

## Overview

Atlantis is a pull request automation tool for Terraform that enables team collaboration, automated workflows, and infrastructure as code reviews. This integration combines Atlantis with Atmos to provide comprehensive multi-account infrastructure management through pull requests.

## Features

- Automatic Terraform plan/apply on pull request
- Integration with Atmos workflows and stacks
- Component and stack auto-detection with robust parsing
- Pull request commenting with detailed plan results
- Auto-merge capability (optional)
- Parallel execution for faster processing
- Enhanced security for production environments
- Multi-account authentication management
- Robust error handling with retry logic
- Health monitoring and logging
- Production-specific approval workflows
- Security policy enforcement

## Architecture

The integration consists of the following components:

1. **Custom Atlantis Docker Image**: Enhanced with Atmos and supporting tools
2. **Configuration Files**: 
   - `atlantis.yaml`: Defines workflows and repo-specific settings
   - `Dockerfile`: Creates the custom Atlantis image with Atmos support
3. **Helper Scripts**:
   - `assume-role.sh`: Manages AWS cross-account authentication
   - `atmos-wrapper.sh`: Provides error handling and logging
4. **Workflow Definitions**: Standard and production-specific workflows
5. **Pre-workflow Hooks**: Intelligent component and stack detection

## Setup Instructions

### Prerequisites

1. A GitHub repository containing your Atmos configuration
2. Permissions to configure webhook on your repository
3. A server to host Atlantis (or Docker for local testing)
4. GitHub personal access token with repo permissions
5. AWS accounts configured with appropriate cross-account roles

### Installation

#### Using Docker (Recommended)

1. Build the custom Atlantis image with Atmos:

```bash
docker build -t atlantis-atmos:latest .
```

2. Create an accounts.json file for multi-account mapping:

```json
{
  "dev": "123456789012",
  "staging": "234567890123",
  "prod": "345678901234"
}
```

3. Run the Atlantis server:

```bash
docker run -p 4141:4141 \
  -e GITHUB_TOKEN=<your-github-token> \
  -e GITHUB_WEBHOOK_SECRET=<your-webhook-secret> \
  -e REPO_ALLOWLIST=github.com/your-org/* \
  -e AWS_REGION=us-west-2 \
  -v ~/.aws:/root/.aws \
  -v $(pwd)/accounts.json:/atlantis/accounts.json \
  atlantis-atmos:latest
```

4. Configure GitHub webhook to point to your Atlantis server endpoint:
   - URL: `https://your-atlantis-server/events`
   - Content type: `application/json`
   - Secret: Same as `GITHUB_WEBHOOK_SECRET`
   - Events: Select `Pull request`, `Push`, and `Issue comment`

#### Manual Installation

1. Install Atlantis according to the [official documentation](https://www.runatlantis.io/docs/installation-guide.html)
2. Install Atmos v1.44.0 or later
3. Install required tools: jq, yq, aws-cli, and bash
4. Copy all files from this directory to your Atlantis server
5. Configure Atlantis to use the provided repo config

## Configuration

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `GITHUB_TOKEN` | GitHub personal access token | Yes | - |
| `GITHUB_WEBHOOK_SECRET` | Secret for verifying GitHub webhooks | Yes | - |
| `REPO_ALLOWLIST` | List of repositories Atlantis will respond to | Yes | - |
| `AWS_REGION` | Default AWS region | No | us-west-2 |
| `ATMOS_VERSION` | Atmos version to use | No | 1.44.0 |
| `MAX_RETRIES` | Maximum retry attempts for commands | No | 3 |

### AWS Authentication

Atlantis needs access to your AWS credentials for multi-account deployments. Configure one of the following methods:

1. **Role Assumption (Recommended)**
   - Create IAM roles in each account with appropriate permissions
   - Create an accounts.json mapping file with account names and IDs
   - The assume-role.sh script will handle cross-account authentication

2. **Volume Mounting**
   - Mount your AWS credentials directory to the container
   - Ensure profiles are configured for each account

3. **IAM Instance Profiles**
   - If running on AWS EC2, use instance profiles
   - Configure appropriate permissions for the instance role

## Usage

### Creating Pull Requests

When you create a pull request that modifies Terraform files:

1. Atlantis will automatically detect the changes
2. Atlantis will determine the component and stack based on file paths
3. For production environments, additional security checks will be performed
4. Atlantis will run `atmos terraform plan` and post detailed results as a comment
5. After required approvals, use comment commands to apply changes

### Atlantis Commands

Comment on the pull request with:

| Command | Description | Example |
|---------|-------------|---------|
| `atlantis plan` | Trigger plan for all changes | `atlantis plan` |
| `atlantis apply` | Apply all planned changes | `atlantis apply` |
| `atlantis plan -d [component]` | Plan specific component | `atlantis plan -d vpc` |
| `atlantis apply -d [component]` | Apply specific component | `atlantis apply -d vpc` |
| `atlantis plan -- component=[name] stack=[stack]` | Explicitly specify component/stack | `atlantis plan -- component=vpc stack=acme-dev-us-east-1` |

## Security Considerations

The integration implements several security best practices:

1. **Production Safeguards**
   - Additional approval requirements for production environments
   - Enhanced security checks before planning/applying
   - Validation against high-risk configurations

2. **Credential Security**
   - No permanent credentials stored in the container
   - Cross-account access using temporary session tokens
   - Least-privilege roles for each account

3. **Operational Security**
   - Plan output scanning for sensitive information
   - Health checks and container security features
   - Secure handling of webhook secrets

4. **Compliance Checks**
   - Production workflows automatically check for:
     - No IAM users or access keys in production
     - No public access configurations
     - Proper encryption settings

## Multi-Account Management

The integration supports Atmos's multi-account architecture through:

1. **Account Detection**
   - Intelligent parsing of stack names to determine account context
   - Properly formatted stack names (`tenant-account-environment`)

2. **Cross-Account Authentication**
   - Dynamic role assumption for each detected account
   - Secure credential management using temporary tokens
   - Caching of assumed role credentials for efficiency

3. **Account-Specific Workflows**
   - Production-specific workflows with enhanced security
   - Different validation rules per account type
   - Proper isolation between account operations

## Advanced Configuration

### Custom Workflows

You can define custom workflows in the `atlantis.yaml` file:

```yaml
workflows:
  custom:
    plan:
      steps:
      - run: custom-script.sh
      - run: atmos terraform plan $COMPONENT -s $STACK
```

### Custom Approval Requirements

For stricter control in production:

```yaml
repos:
  - id: github.com/your-org/repo
    apply_requirements:
      - approved-by-security-team:prod
      - num-approvals=2
```

### Integration with External Systems

Add notifications or external validations:

```yaml
repos:
  - id: github.com/your-org/repo
    pre_workflow_hooks:
      - run: notify-slack.sh "Starting Terraform changes for $COMPONENT"
    post_workflow_hooks:
      - run: update-cmdb.sh $COMPONENT $STACK
```

## Troubleshooting

### Common Issues

1. **Component/stack not detected**
   - Error: "Could not automatically determine component and stack"
   - Solution: Ensure file paths follow standard structure or specify manually
   - Debug: Check pre-workflow hook output in logs

2. **AWS authentication failures**
   - Error: "Error assuming role" or "Unable to locate credentials"
   - Solution: Verify IAM roles and accounts.json configuration
   - Debug: Check logs for AWS credential errors

3. **Webhook failures**
   - Error: Webhook not triggering Atlantis
   - Solution: Verify webhook configuration and server connectivity
   - Debug: Check GitHub webhook delivery logs

4. **YAML parsing errors**
   - Error: "Failed to parse YAML"
   - Solution: Install yq tool or fix formatting issues
   - Debug: Check logs for specific parsing errors

### Logs and Debugging

- Logs are stored in `/atlantis/logs/` with timestamped filenames
- Run Atlantis with increased verbosity: `--log-level=debug`
- The atmos-wrapper script provides detailed logging for each command
- Check webhook delivery in GitHub repository settings

## Version Compatibility

This integration has been tested with:

- Atmos v1.44.0 or later
- Terraform v1.5.0 or later
- AWS Provider v4.9.0 or later
- Atlantis v0.24.1 or later
- Docker 20.10.x or later

## Additional Resources

- [Atlantis Documentation](https://www.runatlantis.io/docs/)
- [Atmos Documentation](https://atmos.tools/)
- [GitHub Webhook Documentation](https://docs.github.com/en/developers/webhooks-and-events/webhooks/about-webhooks)
- [AWS STS Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html)
- [Terraform PR-Driven Workflow Guide](../../docs/pr-driven-workflow.md)
- [Multi-Account Architecture Guide](../../docs/multi-account-architecture.md)