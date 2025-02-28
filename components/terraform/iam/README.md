# IAM Component

_Last Updated: February 28, 2025_

## Overview

This component manages AWS Identity and Access Management (IAM) resources, with a focus on cross-account roles and policies for resource management in multi-account environments.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                       IAM Component                         │
└───────────────────────────┬────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  ┌─────────────────────┐     ┌───────────────────────────┐ │
│  │                     │     │                           │ │
│  │  Cross-Account      │     │    Trust                  │ │
│  │  IAM Roles          │────►│    Relationships          │ │
│  │                     │     │                           │ │
│  └─────────────────────┘     └───────────────────────────┘ │
│            │                                               │
│            │                                               │
│            ▼                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   IAM Policies                       │   │
│  │                                                      │   │
│  │  ┌─────────────────┐      ┌────────────────────┐    │   │
│  │  │ Account Setup   │      │ Resource           │    │   │
│  │  │ Policy          │      │ Management Policy  │    │   │
│  │  └─────────────────┘      └────────────────────┘    │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

The IAM component creates cross-account roles and policies that allow trusted entities from specified AWS accounts to assume roles and perform actions in the target account. The component establishes:

1. A cross-account IAM role with a trust policy that allows specified AWS accounts to assume the role
2. A main IAM policy with account setup permissions (user/group/policy management)
3. A resource management policy for EC2, S3, RDS, and other AWS services

## Features

- Create cross-account IAM roles with customizable trust relationships
- Define IAM policies for account setup and resource management
- Apply consistent tagging to IAM resources
- Enforce least privilege with granular permissions
- Support multi-account AWS environments

## Usage

```yaml
components:
  terraform:
    iam:
      vars:
        region: us-east-1
        cross_account_role_name: "CrossAccountAccessRole"
        trusted_account_ids: 
          - "123456789012"
          - "987654321098"
        policy_name: "CrossAccountAccessPolicy"
        tags:
          Environment: "production"
          Project: "infrastructure"
          Owner: "platform-team"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| cross_account_role_name | Name of the cross-account IAM role | `string` | n/a | yes |
| trusted_account_ids | List of AWS account IDs that are allowed to assume the cross-account role | `list(string)` | n/a | yes |
| policy_name | Name of the IAM policy to be attached to the cross-account role | `string` | n/a | yes |
| tags | Tags to apply to the IAM resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cross_account_role_arn | ARN of the cross-account IAM role |
| cross_account_role_name | Name of the cross-account IAM role |
| cross_account_policy_arn | ARN of the cross-account IAM policy |
| cross_account_policy_name | Name of the cross-account IAM policy |

## Examples

### Basic Cross-Account Role

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/basic:
      vars:
        region: us-west-2
        cross_account_role_name: "DevOpsAccessRole"
        trusted_account_ids: 
          - "123456789012"
        policy_name: "DevOpsAccessPolicy"
        tags:
          Environment: "dev"
          ManagedBy: "terraform"
```

### Multiple Trusted Accounts

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/multi-account:
      vars:
        region: us-east-1
        cross_account_role_name: "CrossEnvAccessRole"
        trusted_account_ids: 
          - "123456789012"  # Development account
          - "234567890123"  # Staging account
          - "345678901234"  # Security audit account
        policy_name: "CrossEnvironmentAccessPolicy"
        tags:
          Environment: "production"
          ManagedBy: "terraform"
          Purpose: "cross-environment-access"
```

### Production CI/CD Access

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/cicd:
      vars:
        region: us-east-1
        cross_account_role_name: "CICDDeploymentRole"
        trusted_account_ids: 
          - "987654321098"  # CI/CD account
        policy_name: "DeploymentAccessPolicy"
        tags:
          Environment: "production"
          ManagedBy: "terraform" 
          Purpose: "continuous-deployment"
```

## Implementation Best Practices

1. **Security**:
   - Follow the principle of least privilege when granting permissions
   - Use managed policies when possible for easier maintenance
   - Regularly audit and rotate credentials
   - Use roles instead of long-term access keys
   - Implement MFA for critical operations

2. **Organization**:
   - Use consistent naming conventions for all IAM resources
   - Use tags for resource organization and cost allocation
   - Group related permissions into logical policies
   - Document the purpose of each role and policy

3. **Cross-Account Access**:
   - Limit the session duration for assumed roles
   - Implement strict conditions in trust relationships
   - Audit cross-account access regularly
   - Consider implementing IP-based restrictions

## Troubleshooting

### Common Issues

1. **Access Denied When Assuming Role**:
   - Verify that the trust relationship is correctly configured
   - Check that the trusted account IDs are correct
   - Ensure the user has permission to call `sts:AssumeRole`
   - Verify that any conditional elements (like MFA) are satisfied

2. **Policy Too Permissive**:
   - Review the policy statements to ensure they follow least privilege
   - Use IAM Access Analyzer to identify overly permissive policies
   - Consider using more specific resource ARNs instead of wildcards

3. **Role Not Visible**:
   - Ensure you're looking in the correct AWS account
   - Verify that the role was created successfully
   - Check for naming conflicts or policy errors during deployment

4. **Policy Changes Not Taking Effect**:
   - Remember that IAM changes can take time to propagate globally
   - Verify the policy document is valid JSON and doesn't exceed size limits
   - Check CloudTrail for any errors during policy application

## Related Resources

- [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Cross-Account Access](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)
- [AWS STS Documentation](https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html)