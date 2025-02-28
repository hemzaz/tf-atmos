# Atmos Integrations

This directory contains integrations for using Atmos with popular CI/CD and automation tools. Each subdirectory includes configuration files, documentation, and examples for integrating Atmos with specific platforms.

## Available Integrations

- [Jenkins](./jenkins/): Automated pipelines for running Atmos commands in Jenkins
- [Atlantis](./atlantis/): Pull request automation for Terraform workflows using Atmos

## Common Features

All integrations provide:

1. **Automated workflows** for plan, apply, and destroy operations
2. **Multi-environment support** using Atmos's tenant/account/environment model
3. **Component-specific targeting** for granular infrastructure management
4. **Pre-flight validation** with linting and validation checks
5. **Secure credential handling** following best practices

## Choosing an Integration

| Integration | Best For | Key Features |
|-------------|----------|--------------|
| Jenkins | Pipeline-driven workflows, complex CI/CD | Customizable pipeline stages, integration with existing Jenkins infrastructure |
| Atlantis | Pull request-driven workflows, GitHub integration | Automatic PR comments, merge checks, simplified developer experience |

## Setup Requirements

To use these integrations, you'll need:

1. A working Atmos configuration in your repository
2. Access to the appropriate CI/CD system (Jenkins, GitHub, etc.)
3. AWS credentials configured for the CI/CD environment
4. Proper permissions to create webhooks, runners, or pipelines

## Custom Integrations

If you need to integrate Atmos with other CI/CD systems:

1. Use the existing integrations as a template
2. Ensure AWS credentials are securely passed to the Atmos commands
3. Follow the workflow patterns established in the Atmos documentation
4. Create appropriate triggers for plan, apply, and destroy operations

## Support

For issues with these integrations:

1. Check the README in the specific integration directory
2. Refer to the [Atmos documentation](https://atmos.tools/)
3. Search or open issues in the [Atmos repository](https://github.com/cloudposse/atmos)

## Contributing

To contribute new integrations or improvements:

1. Follow the structure of existing integrations
2. Include comprehensive documentation and examples
3. Test thoroughly with different Atmos configurations
4. Submit a pull request with your changes