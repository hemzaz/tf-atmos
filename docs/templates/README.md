# Infrastructure Templates

Terminal-first templates for rapid infrastructure deployment and development.

## 🎯 Template Categories

### 1. Stack Templates
Complete environment configurations ready for deployment.

```bash
# Generate new stack from template
./scripts/manifest-generator.sh template stack my-new-environment

# Available stack types:
- minimal-stack     # Basic VPC + Security Groups
- full-stack       # Complete infrastructure with EKS, RDS, monitoring
- microservices    # Container-optimized with EKS + addons
- serverless       # Lambda + API Gateway + DynamoDB
```

### 2. Component Templates
Individual Terraform components following best practices.

```bash
# Generate new component
./scripts/manifest-generator.sh template component my-service

# Browse available components:
ls templates/components/
```

### 3. Workflow Templates
Automation workflows for common operational patterns.

```bash
# Copy workflow template
cp templates/workflows/deployment-pipeline.yaml workflows/my-deployment.yaml
```

### 4. Configuration Templates
Reusable configuration patterns for different environments.

```bash
# Environment-specific configs
cp templates/configs/production.yaml stacks/orgs/myorg/prod/config.yaml
```

## 🚀 Quick Start

### Create New Environment
```bash
# 1. Generate stack template
./scripts/manifest-generator.sh template stack production-env myorg prod production us-east-1

# 2. Customize configuration
vim stacks/orgs/myorg/prod/us-east-1/production/main.yaml

# 3. Validate and deploy
gaia workflow validate --tenant myorg --account prod --environment production
gaia workflow plan-environment --tenant myorg --account prod --environment production
```

### Create New Component
```bash
# 1. Generate component template
./scripts/manifest-generator.sh template component cache-layer

# 2. Implement component logic
vim components/terraform/cache-layer/main.tf

# 3. Test component
gaia terraform validate cache-layer --stack myorg-prod-production
```

## 📋 Template Usage Patterns

### Power User Shortcuts
```bash
# Quick component from existing
cp -r templates/components/web-service components/terraform/my-api
sed -i 's/web-service/my-api/g' components/terraform/my-api/*.tf

# Batch environment creation
for env in staging production; do
  ./scripts/manifest-generator.sh template stack $env-infra myorg prod $env
done
```

### API Integration
```bash
# Start API server
gaia serve --port 8080

# Generate via API (future feature)
curl -X POST -H "Content-Type: application/json" \
     -d '{"type":"stack","name":"my-env","tenant":"myorg"}' \
     http://localhost:8080/templates/generate
```

## 🛠️ Template Development

### Create Custom Templates
1. Copy existing template as starting point
2. Modify for your use case
3. Test with real deployment
4. Document usage patterns

### Template Best Practices
- Use descriptive variable names
- Include comprehensive README
- Follow security best practices
- Include validation rules
- Provide usage examples

## 📚 Reference

- **Atmos Documentation**: https://atmos.tools/
- **Terraform Best Practices**: [AWS Well-Architected](https://aws.amazon.com/architecture/well-architected/)
- **Component Guidelines**: See `CLAUDE.md` for coding standards

---

**Built for developers who value speed, consistency, and terminal-first workflows.**