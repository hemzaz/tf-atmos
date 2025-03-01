# AWS Authentication for Atmos Multi-Account Architecture

_Last Updated: February 28, 2025_

This guide describes the authentication patterns and best practices for working with AWS in a multi-account environment using Atmos.

## Table of Contents

- [Overview](#overview)
- [Authentication Patterns](#authentication-patterns)
- [Cross-Account Role Assumption](#cross-account-role-assumption)
- [CI/CD Authentication](#cicd-authentication)
- [Local Development Authentication](#local-development-authentication)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Related Resources](#related-resources)

## Overview

Atmos supports deploying infrastructure across multiple AWS accounts. Secure authentication is crucial for maintaining a proper security boundary between these accounts while enabling efficient management. This guide details the authentication patterns used in different scenarios.

## Authentication Patterns

| Pattern | Use Case | Advantages | Considerations |
|---------|----------|------------|----------------|
| **IAM Roles** | CI/CD pipelines, automation | No long-term credentials, auditability | Requires role configuration in each account |
| **Cross-Account Roles** | Managing multiple accounts | Central management, least privilege | Setup complexity, trust relationships |
| **AWS SSO** | Developer workstations | Simplified user management, MFA | Additional identity provider configuration |
| **AWS Profiles** | Local development | Simple configuration | Requires credential refreshing |

## Cross-Account Role Assumption

The recommended approach for multi-account management is using cross-account roles with centralized management:

### Trust Architecture

1. **Management Account**: Contains IAM users/roles with permission to assume roles in other accounts
2. **Member Accounts**: Contain IAM roles that trust the management account
3. **Service Accounts**: Specialized roles for services that operate across accounts

### Role Structure

```
Management Account (123456789012)
├── OrganizationAccountAccessRole
└── AtmosDeploymentRole

Member Account - Dev (234567890123)
├── AtmosDeploymentRole (trusts Management's AtmosDeploymentRole)
└── AtmosReadOnlyRole (trusts Management's OrganizationAccountAccessRole)

Member Account - Prod (345678901234)
├── AtmosDeploymentRole (trusts Management's AtmosDeploymentRole, requires MFA)
└── AtmosReadOnlyRole (trusts Management's OrganizationAccountAccessRole)
```

### Implementation with Terraform

The [iam component](../components/terraform/iam/) creates these cross-account roles:

```hcl
# Example from components/terraform/iam/cross-account-roles.tf
resource "aws_iam_role" "atmos_deployment_role" {
  name = "AtmosDeploymentRole"
  
  assume_role_policy = templatefile("${path.module}/policies/cross-account-assume-role.json", {
    trusted_account_id = var.management_account_id
    require_mfa        = var.environment == "prod" ? true : false
  })
  
  # Additional role policies...
}
```

## CI/CD Authentication

### Jenkins Integration

The [Jenkins integration](../integrations/jenkins/README.md) uses role assumption with session credentials:

1. Jenkins stores the management account role ARN as a credential
2. Pipeline retrieves the role ARN for each target account
3. STS AssumeRole operation generates temporary credentials
4. Credentials are used for the duration of the pipeline

```groovy
// Example from integrations/jenkins/Jenkinsfile
withCredentials([string(credentialsId: "${params.ACCOUNT}-role-arn", variable: 'AWS_ROLE_ARN')]) {
    sh """
        export AWS_ROLE_ARN=${AWS_ROLE_ARN}
        export AWS_ROLE_SESSION_NAME=${params.AWS_ROLE_SESSION_NAME}
        aws sts get-caller-identity
    """
}
```

### Atlantis Integration

The [Atlantis integration](../integrations/atlantis/README.md) handles cross-account access with:

1. Account mapping in a configuration file (`accounts.json`)
2. Helper script for role assumption (`assume-role.sh`)
3. Credential caching for efficiency
4. Automatic detection of which account to use based on stack name

```bash
#!/usr/bin/env bash
# Example from integrations/atlantis/scripts/assume-role.sh
ACCOUNT_ID=$(jq -r ".$ACCOUNT // empty" /atlantis/accounts.json)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
TEMP_CREDS=$(aws sts assume-role \
    --role-arn "${ROLE_ARN}" \
    --role-session-name "${SESSION_NAME}" \
    --duration-seconds "${DURATION}" \
    --output json)
```

## Local Development Authentication

For local development, configure AWS profiles in `~/.aws/credentials` and `~/.aws/config`:

```ini
# ~/.aws/credentials
[management]
aws_access_key_id = AKIAXXXXXXXXXXXXXXXX
aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# ~/.aws/config
[profile management]
region = us-west-2
output = json

[profile dev]
region = us-west-2
role_arn = arn:aws:iam::234567890123:role/AtmosDeploymentRole
source_profile = management
mfa_serial = arn:aws:iam::123456789012:mfa/user@example.com

[profile prod]
region = us-west-2
role_arn = arn:aws:iam::345678901234:role/AtmosDeploymentRole
source_profile = management
mfa_serial = arn:aws:iam::123456789012:mfa/user@example.com
```

### Using Profiles with Atmos

```bash
#!/usr/bin/env bash
# Specify AWS profile when running Atmos commands
export AWS_PROFILE=dev
atmos terraform plan vpc -s tenant-dev-us-west-2

# Or specify directly in the command
AWS_PROFILE=prod atmos terraform plan vpc -s tenant-prod-us-west-2
```

## Best Practices

### Credential Management

1. **Never store AWS credentials in code repositories**
2. **Use temporary credentials** via role assumption whenever possible
3. **Enforce MFA** for human access to production accounts
4. **Implement credential rotation** policies
5. **Set appropriate credential timeouts** (shorter for higher privilege roles)

### Permission Boundaries

1. **Apply permission boundaries** to limit maximum permissions
2. **Use separate roles** for different responsibilities
3. **Follow least privilege** principles for each role
4. **Regularly audit** permissions for excess access

### Secure Credential Storage

1. **Use credential managers** for CI/CD systems
2. **Encrypt credential storage** at rest
3. **Implement access logging** for credential usage
4. **Establish emergency access** procedures

### IAM Best Practices

1. **Create functional roles** rather than per-user roles
2. **Standardize naming conventions** for roles across accounts
3. **Document trust relationships** between accounts
4. **Implement SCPs** (Service Control Policies) to enforce guardrails

## Troubleshooting

### Common Issues

1. **Access Denied Errors**
   - Check role permissions and trust relationships
   - Verify session token expiration
   - Ensure MFA is provided when required
   - Check for SCPs that may be blocking access

2. **Missing Credentials**
   - Verify environment variables are properly set
   - Check AWS profile configuration
   - Confirm credential provider chain is working as expected

3. **Permission Issues**
   - Use `aws sts get-caller-identity` to verify the assumed identity
   - Check IAM policies for the role being used
   - Review CloudTrail logs for denied actions

4. **Session Expiration**
   - Implement token refresh logic for long-running operations
   - Extend session duration where appropriate
   - Check for automatic timeouts in the credential provider

## Related Resources

- [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)
- [IAM Role Patterns](iam-role-patterns-guide.md)
- [Security Best Practices](security-best-practices-guide.md)
- [Jenkins Integration Guide](../integrations/jenkins/README.md)
- [Atlantis Integration Guide](../integrations/atlantis/README.md)