# Jenkins Integration for Atmos

This directory contains the configuration needed to integrate Jenkins with Atmos for automated Terraform workflow execution.

## Features

- Automated pipeline for running Atmos workflows
- Supports all Atmos commands (plan, apply, destroy)
- Multi-environment support (tenant, account, environment)
- Component-specific targeting capabilities
- Pre-flight checks with linting and validation

## Setup Instructions

### Prerequisites

1. Jenkins server with Docker support
2. AWS credentials properly configured for Jenkins
3. Network access to AWS services

### Installation

1. Add this Jenkinsfile to your Jenkins pipeline configuration
2. Configure Jenkins credentials for AWS access
3. Set up webhook triggers from your Git provider (optional)

### Required Jenkins Plugins

- Pipeline
- Docker Pipeline
- Git Integration
- Credentials Binding

## Usage

### Running the Pipeline

The pipeline can be triggered manually with the following parameters:

- **TENANT**: The tenant name (e.g., `organization`)
- **ACCOUNT**: The AWS account name (e.g., `dev`, `prod`)
- **ENVIRONMENT**: The environment name (e.g., `us-east-1`)
- **ACTION**: Choose between `plan`, `apply`, or `destroy`
- **COMPONENT**: (Optional) Specify a single component to target instead of the entire environment

### Examples

#### Planning Changes for an Entire Environment

This will run a plan for all components in the specified environment:

```
TENANT: acme
ACCOUNT: dev
ENVIRONMENT: us-east-1
ACTION: plan
COMPONENT: (leave empty)
```

#### Applying a Single Component

This will apply changes only for the specified component:

```
TENANT: acme
ACCOUNT: prod
ENVIRONMENT: us-west-2
ACTION: apply
COMPONENT: vpc
```

## Security Considerations

- The pipeline uses Docker isolation for running Terraform
- AWS credentials are securely mounted into the container
- No sensitive values are exposed in logs
- Workspace is cleaned after each run

## Troubleshooting

### Common Issues

1. **AWS credential issues**: Ensure credentials are properly configured in Jenkins
2. **Missing Atmos configuration**: Verify atmos.yaml exists in your repository
3. **Component not found**: Check that the component exists and is properly configured

### Logs and Debugging

Pipeline logs can be viewed in the Jenkins UI. For detailed debugging:

1. Enable verbose mode by adding `-v` to the Atmos commands in the Jenkinsfile
2. Check workspace contents before cleanup by commenting out the `cleanWs()` command
3. Add debug echo statements to the pipeline for variable inspection

## Customization

The Jenkinsfile can be customized for your specific needs:

- Add additional stages for testing or security scanning
- Modify the Docker image to include custom tools
- Add approval gates for production environments
- Integrate with notification systems (Slack, email, etc.)

For more detailed information on the Atmos commands, refer to the [Atmos documentation](https://atmos.tools/cli/commands/).