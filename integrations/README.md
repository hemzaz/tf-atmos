# Atmos Integrations

_Last Updated: February 28, 2025_

This directory contains integrations for using Atmos with popular CI/CD and automation tools. Each subdirectory includes configuration files, documentation, and examples for integrating Atmos with specific platforms.

## Table of Contents

- [Overview](#overview)
- [Available Integrations](#available-integrations)
- [Common Features](#common-features)
- [Choosing an Integration](#choosing-an-integration)
- [Setup Requirements](#setup-requirements)
- [Security Considerations](#security-considerations)
- [Custom Integrations](#custom-integrations)
- [Versioning](#versioning)
- [Support](#support)
- [Contributing](#contributing)

## Overview

Atmos integrations provide standardized interfaces between Atmos and external CI/CD platforms. These integrations enable automated infrastructure workflows, consistent approval processes, and secure credential handling across different deployment environments.

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
6. **Error handling and retry logic** for improved reliability
7. **Cross-account authentication** for multi-account AWS environments
8. **Production safeguards** with approval gates for sensitive environments

## Choosing an Integration

| Integration | Best For | Key Features |
|-------------|----------|--------------|
| Jenkins | Pipeline-driven workflows, complex CI/CD | Customizable pipeline stages, integration with existing Jenkins infrastructure, automated testing |
| Atlantis | Pull request-driven workflows, GitHub integration | Automatic PR comments, merge checks, simplified developer experience, component auto-detection |

## Setup Requirements

To use these integrations, you'll need:

1. A working Atmos configuration in your repository
2. Access to the appropriate CI/CD system (Jenkins, GitHub, etc.)
3. AWS credentials configured for the CI/CD environment
4. Proper permissions to create webhooks, runners, or pipelines
5. Docker support (for containerized implementations)

## Security Considerations

When implementing these integrations, ensure you follow these security best practices:

1. **Credential Management**
   - Use AWS IAM roles with assumed roles for cross-account access
   - Never store AWS access keys in configuration files or environment variables
   - Rotate all secrets and access tokens regularly

2. **Access Controls**
   - Implement approval requirements for production environments
   - Use branch protection rules to prevent direct pushes to protected branches
   - Limit administrative access to CI/CD systems

3. **Scanning and Validation**
   - Enable security scanning in CI/CD pipelines
   - Validate Terraform plans for security risks before applying
   - Monitor for drift and unauthorized changes

## Custom Integrations

If you need to integrate Atmos with other CI/CD systems:

1. Use the existing integrations as a template
2. Ensure AWS credentials are securely passed to the Atmos commands
3. Follow the workflow patterns established in the Atmos documentation
4. Create appropriate triggers for plan, apply, and destroy operations
5. Implement proper error handling and logging
6. Add cross-account authentication support

## Versioning

All integrations are versioned with Atmos and follow semantic versioning:

- Each integration specifies compatible Atmos versions
- Major version changes indicate breaking changes
- Minor version changes add new features with backward compatibility
- Patch version changes include bug fixes and minor improvements

Current version compatibility:
- Atmos: v1.44.0 or later
- Terraform: v1.5.0 or later
- AWS Provider: v4.9.0 or later

## Support

For issues with these integrations:

1. Check the README in the specific integration directory
2. Refer to the [Atmos documentation](https://atmos.tools/)
3. Search or open issues in the [Atmos repository](https://github.com/cloudposse/atmos)
4. Join the community Slack channel for real-time support

## Contributing

To contribute new integrations or improvements:

1. Follow the structure of existing integrations
2. Include comprehensive documentation and examples
3. Test thoroughly with different Atmos configurations
4. Implement error handling and security best practices
5. Submit a pull request with your changes
6. Ensure all documentation follows the [Documentation Style Guide](../docs/documentation-style-guide.md)