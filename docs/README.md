# Terraform/Atmos Infrastructure Documentation

Welcome to the comprehensive documentation for the Terraform/Atmos infrastructure project. This documentation covers all aspects of the infrastructure-as-code platform, from basic setup to advanced operational procedures.

## 📖 Documentation Structure

### 🏗️ [Architecture](architecture/)
Core architectural concepts and design patterns
- [Architecture Overview](architecture/ARCHITECTURE_DIAGRAM.md)
- [Deployment Architecture Guide](architecture/DEPLOYMENT_ARCHITECTURE_GUIDE.md)
- [Backend Architecture Optimization](architecture/BACKEND_ARCHITECTURE_OPTIMIZATION.md)
- [Cloud Architecture Optimization Plan](architecture/CLOUD_ARCHITECTURE_OPTIMIZATION_PLAN.md)
- [Security Best Practices](architecture/security-best-practices-guide.md)

### 🔧 [Components](components/)
Terraform components and examples
- [API Gateway Integration Guide](components/api-gateway-integration-guide.md)
- [Certificate Management Guide](components/certificate-management-guide.md)
- [EKS Guide](components/eks-guide.md)
- [IAM Role Patterns Guide](components/iam-role-patterns-guide.md)
- [Secrets Manager Guide](components/secrets-manager-guide.md)
- [Terraform Components Guide](components/terraform-components-guide.md)
- [Terraform Components Reference](components/terraform/)
- [Examples](components/examples/)

### 📚 [Guides](guides/)
User guides and best practices
- [Developer Guide](guides/DEVELOPER_GUIDE.md)
- [Terminal Power User Guide](guides/TERMINAL_POWER_USER_GUIDE.md)
- [Shell Compatibility Guide](guides/SHELL_COMPATIBILITY_FIXES.md)
- [Guidelines](guides/GUIDELINES.md)
- [Environment Guide](guides/environment-guide.md)

### ⚙️ [Operations](operations/)
Operational procedures and troubleshooting
- [AWS Setup](operations/AWS_SETUP.md)
- [Setup Guide](operations/SETUP.md)
- [Troubleshooting](operations/TROUBLESHOOTING.md)
- [Disaster Recovery Guide](operations/disaster-recovery-guide.md)
- [Disaster Recovery Playbook](operations/disaster-recovery-playbook.md)
- [Coordination Framework](operations/AGENT_COORDINATION_FRAMEWORK.md)

### 📋 [Reference](reference/)
Technical reference and API documentation
- [Workflow Analysis](reference/WORKFLOW_ANALYSIS.md)
- [Task Dependencies](reference/TASK_DEPENDENCIES.md)
- [Terraform Development Standards](reference/terraform-development-standards.md)
- [Gaia CLI Reference](reference/gaia-cli.md)
- [Integrations](reference/integrations/)
- [Scripts](reference/scripts/)
- [Stacks](reference/stacks/)

### 📝 [Templates](templates/)
Infrastructure templates and patterns
- [Templates Overview](templates/README.md)
- [Web Service Component](templates/web-service-component.md)

### 🔄 [Workflows](workflows/)
Automation workflows and CI/CD
- [CI/CD Integration Guide](workflows/cicd-integration-guide.md)
- [Terraform Development Guide](workflows/terraform-development-guide.md)
- [Workflows Overview](workflows/workflows-overview.md)

## 🚀 Quick Start

1. **Setup**: Start with [Operations > Setup Guide](operations/SETUP.md)
2. **Architecture**: Understand the [Architecture Overview](architecture/ARCHITECTURE_DIAGRAM.md)
3. **Development**: Follow the [Developer Guide](guides/DEVELOPER_GUIDE.md)
4. **Components**: Explore [Components](components/) for specific infrastructure patterns

## 🎯 Key Concepts

- **Atmos**: Stack configuration management and workflow orchestration
- **Terraform**: Infrastructure as Code implementation
- **Multi-tenant**: Support for multiple organizations and environments
- **Terminal-first**: Command-line focused development experience
- **Gaia CLI**: Python-based CLI tool for enhanced workflows

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

## 📞 Support

- **Issues**: Check [Troubleshooting Guide](operations/TROUBLESHOOTING.md)
- **Development**: See [Developer Guide](guides/DEVELOPER_GUIDE.md)
- **Operations**: Reference [Operations](operations/) documentation

## 🏷️ Project Structure

```
docs/
├── architecture/     # System design and architecture
├── components/       # Terraform components and examples
├── guides/          # User guides and tutorials
├── operations/      # Operational procedures
├── reference/       # Technical reference
├── templates/       # Infrastructure templates
└── workflows/       # Automation workflows
```

---

*This documentation is automatically maintained and updated as the project evolves.*
