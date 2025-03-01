# Pull Request-Driven Infrastructure Workflow

_Last Updated: February 28, 2025_

This guide describes the pull request-driven workflow for infrastructure changes using Atlantis and Atmos. This approach provides reliable, auditable, and collaborative infrastructure management.

## Table of Contents

- [Overview](#overview)
- [Benefits](#benefits)
- [Workflow Stages](#workflow-stages)
- [Implementation with Atlantis](#implementation-with-atlantis)
- [Best Practices](#best-practices)
- [Example Pull Request](#example-pull-request)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [Related Resources](#related-resources)

## Overview

The PR-driven workflow brings software development best practices to infrastructure management. Changes to infrastructure code go through a structured review process using pull requests, automated validation, and formal approvals before being applied to production environments.

## Benefits

- **Code Review**: Infrastructure changes receive the same level of scrutiny as application code
- **Audit Trail**: Complete history of infrastructure changes with reviewers and approvals
- **Automated Validation**: Pre-flight checks identify issues before changes are applied
- **Collaboration**: Team members can comment, suggest improvements, and approve changes
- **Documentation**: PR descriptions provide context for infrastructure changes
- **Rollback Capability**: Clear commit history enables targeted rollbacks if needed

## Workflow Stages

### 1. Feature Branch Creation

1. Create a new branch from the main branch
2. Make infrastructure changes to component configurations
3. Commit changes with descriptive commit messages
4. Push branch to remote repository

### 2. Pull Request Creation

1. Create a pull request with a descriptive title and detailed description
2. Assign appropriate reviewers based on component expertise
3. Add labels based on change types (e.g., "eks-change", "networking", "security")

### 3. Automated Validation

1. Atlantis automatically detects Terraform changes
2. Linting and validation workflows run
3. Atlantis determines affected components and stacks
4. Terraform plan is executed for each component
5. Plan results are posted as comments on the PR

### 4. Code Review

1. Reviewers examine the code changes
2. Reviewers inspect the Terraform plan output
3. Comments and discussions occur within the PR
4. Changes are requested and addressed if needed

### 5. Approval and Apply

1. Required approvals are collected
2. For production changes, additional approvals may be required
3. PR author or approver triggers application using `atlantis apply` comment
4. Atlantis applies the changes and posts results
5. PR is merged upon successful apply

### 6. Post-Apply Validation

1. Automated drift detection verifies applied changes match expected state
2. Any additional verification scripts run
3. Results are posted as comments on the PR

## Implementation with Atlantis

The [Atlantis integration](../integrations/atlantis/README.md) provides a complete implementation of this workflow with:

1. **Automatic Detection**: Identifies affected components from modified files
2. **Component/Stack Matching**: Determines correct stack contexts for each component
3. **Plan Visualization**: Generates clear, readable plan output in PR comments
4. **Security Checks**: Applies additional validations for production environments
5. **Cross-Account Authentication**: Manages AWS credentials for different accounts
6. **Approval Enforcement**: Requires appropriate approvals before apply

### Sample Workflow File

```yaml
# From atlantis.yaml
workflows:
  atmos:
    plan:
      steps:
      - run: atmos workflow validate
      - run: atmos terraform plan $COMPONENT -s $STACK
    apply:
      steps:
      - run: atmos terraform apply $COMPONENT -s $STACK
```

## Best Practices

### PR Creation

1. **Clear Titles**: Use descriptive titles that summarize the change
2. **Detailed Descriptions**: Include the purpose, benefits, and testing approach
3. **One Change Per PR**: Focus each PR on a single logical change
4. **Reasonable Size**: Keep PRs small enough for effective review

### Code Review

1. **Review Plans Carefully**: Examine the terraform plan output for unintended changes
2. **Ask Questions**: Seek clarification on implementation details
3. **Consider Security**: Assess security implications of changes
4. **Verify Compliance**: Ensure changes adhere to organizational policies

### Approval Process

1. **Required Reviewers**: Include both component SMEs and security reviewers
2. **Production Safeguards**: Implement stricter approval requirements for production
3. **Change Windows**: Schedule applies during approved change windows
4. **Post-Apply Review**: Verify the results match expectations after apply

## Example Pull Request

### Title
Add Karpenter Autoscaling to EKS Development Cluster

### Description
```
This PR adds Karpenter autoscaling to our development EKS cluster to improve scaling performance and resource utilization.

## Changes
- Enables the Karpenter addon in the eks-addons component
- Configures custom Karpenter provisioner for spot instances
- Sets resource limits and scaling parameters
- Adds documentation for Karpenter in the EKS autoscaling guide

## Testing
- Tested in sandbox environment
- Verified proper node provisioning with test workloads
- Confirmed graceful node termination

## Security Considerations
- Karpenter uses IRSA with least privilege permissions
- Node identity uses EKS pod identity association
- Pod security standards enforced on provisioned nodes

## Risks and Mitigations
- Risk: Potential over-provisioning
- Mitigation: Added spending limits and max node constraints
```

## Security Considerations

1. **Credential Management**: The Atlantis server needs secure access to AWS accounts
2. **Approval Requirements**: Enforce stricter approval requirements for sensitive changes
3. **Branch Protection**: Prevent direct pushes to protected branches
4. **Webhook Security**: Secure Atlantis webhook with proper authentication

## Troubleshooting

### Common Issues

1. **Component/Stack Detection Failures**
   - Ensure file paths follow the standard structure
   - Check pre-workflow hook logs for detection issues
   - Manually specify component and stack if needed

2. **Plan Failures**
   - Check for input validation errors
   - Verify that the component exists in the repository
   - Ensure AWS credentials are properly configured

3. **Apply Failures**
   - Check for dependency issues between resources
   - Verify that required approvals are in place
   - Look for timeout issues with resource creation

## Related Resources

- [Atlantis Integration Guide](../integrations/atlantis/README.md)
- [CI/CD Best Practices](cicd-integration-guide.md)
- [Component Creation Guide](terraform-component-creation-guide.md)
- [AWS Authentication Guide](aws-authentication.md)