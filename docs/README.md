# AWS Infrastructure Documentation

This directory contains comprehensive documentation for the AWS infrastructure managed with Terraform and Atmos.

## Documentation Structure

### Core Concepts
- [Architecture Guide](core-concepts/architecture-guide.md)
- [Security Best Practices](core-concepts/security-best-practices-guide.md)

### Environment Management
- [Environment Guide](environment-management/environment-guide.md) - Comprehensive guide covering environment creation, templating, and management

### Component Guides
- [EKS Guide](component-guides/eks-guide.md) - Complete guide for EKS clusters, addons, and Istio
- [API Gateway Integration](component-guides/api-gateway-integration-guide.md)
- [Certificate Management](component-guides/certificate-management-guide.md)
- [IAM Role Patterns](component-guides/iam-role-patterns-guide.md)
- [Secrets Manager](component-guides/secrets-manager-guide.md)
- [Terraform Components](component-guides/terraform-components-guide.md) - Component catalog and creation guide

### Operations
- [Disaster Recovery](operations/disaster-recovery-guide.md)
- [Troubleshooting](operations/troubleshooting-guide.md)

### Workflows
- [CI/CD Integration](workflows/cicd-integration-guide.md)
- [Terraform Development](workflows/terraform-development-guide.md)

## Atmos Documentation

For Atmos-specific documentation, see the [atmos-docs](atmos-docs) directory.

## Quick Reference

### Environment Management

```bash
# Create a new environment
./scripts/create-environment.sh \
  --template dev \
  --tenant mycompany \
  --account dev \
  --environment dev-01 \
  --vpc-cidr 10.0.0.0/16

# Deploy an environment
atmos workflow apply-environment \
  tenant=mycompany \
  account=dev \
  environment=dev-01
```

### Component Deployment

```bash
# Plan changes for a component
atmos terraform plan vpc -s mycompany-dev-dev-01

# Apply changes for a component
atmos terraform apply vpc -s mycompany-dev-dev-01
```

### Common Workflows

```bash
# Validate infrastructure
atmos workflow validate

# Run drift detection
atmos workflow drift-detection

# Rotate certificates
atmos workflow rotate-certificate \
  tenant=mycompany \
  account=dev \
  environment=dev-01 \
  certificate_name=*.dev-01.example.com
```
