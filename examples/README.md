# Examples

This directory contains practical examples and code snippets to help you implement common patterns in your Atmos-managed infrastructure.

## Contents

### Available Component Examples

- `vpc/` - VPC configuration with public and private subnets
- `apigateway/` - API Gateway with Lambda integrations
- `eks-addons/` - EKS add-ons with Karpenter and KEDA scaling configurations

### Upcoming Component Examples (In Development)

These examples are being developed and will be available soon:

- RDS configurations 
- EKS cluster setup
- Lambda functions
- Serverless applications
- Networking patterns

### Configuration Examples

- `multi-environment/` - Multi-environment configuration patterns
- `cross-account/` - Cross-account access patterns
- `shared-services/` - Shared services architecture

### Integration Examples

- `ci-cd/` - CI/CD pipeline integration with GitHub Actions and GitLab
- `monitoring/` - Monitoring setup with CloudWatch dashboards and alarms
- `security/` - Security configuration with IAM, KMS, and VPC endpoints

## Usage

Each example directory contains:

1. A `README.md` with detailed explanation and usage instructions
2. Complete code samples that can be copied and adapted
3. Architecture diagrams where applicable

### How to Use the Examples

1. Browse the examples to find a pattern that matches your use case
2. Read the accompanying documentation to understand the implementation
3. Copy the relevant code to your own implementation
4. Customize the code for your specific requirements

## Example Customization

When adapting examples, consider:

1. **Naming** - Update resource names to match your naming conventions
2. **Region** - Adjust regions based on your geographic requirements
3. **Scale** - Modify instance sizes, counts, and capacities
4. **Dependencies** - Update dependencies to reference your existing components
5. **Security** - Review and enhance security configurations

## Best Practices Applied

All examples adhere to the best practices outlined in the CLAUDE.md file, including:

- Proper variable validation
- Comprehensive error handling
- Consistent tagging
- Secure defaults
- Clear documentation
- Infrastructure testing approaches