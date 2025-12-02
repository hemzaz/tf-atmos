# CI/CD Pipeline Documentation

Complete CI/CD automation for Terraform/Atmos infrastructure deployment with zero manual steps.

## Overview

This project implements a comprehensive CI/CD pipeline with:

- Automated testing (unit, integration, smoke, security)
- Multi-environment deployment (dev, staging, production)
- Security scanning (Trivy, Checkov, tfsec, Bandit)
- Drift detection (hourly)
- Cost estimation (Infracost)
- Automated rollback on failure
- Complete audit trail

## Pipeline Architecture

```
┌─────────────┐
│ Pull Request│
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│        CI Pipeline                  │
│  ┌───────────────────────────────┐  │
│  │ 1. Code Quality & Formatting  │  │
│  │    - Terraform fmt check      │  │
│  │    - Python black/flake8      │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 2. Security Scanning          │  │
│  │    - Trivy (vulnerabilities)  │  │
│  │    - Checkov (IaC security)   │  │
│  │    - tfsec (Terraform)        │  │
│  │    - Bandit (Python)          │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 3. Terraform Validation       │  │
│  │    - Atmos lint               │  │
│  │    - Atmos validate           │  │
│  │    - Component validation     │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 4. Infrastructure Plan        │  │
│  │    - Generate Terraform plan  │  │
│  │    - Detect changes           │  │
│  │    - Comment on PR            │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 5. Cost Estimation            │  │
│  │    - Infracost analysis       │  │
│  │    - Comment on PR            │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
       │
       ▼
┌─────────────┐
│ Merge to    │
│ main/master │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│        CD Pipeline                  │
│  ┌───────────────────────────────┐  │
│  │ 1. Deploy to Dev              │  │
│  │    - Automatic deployment     │  │
│  │    - Smoke tests              │  │
│  │    - Health checks            │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 2. Deploy to Staging          │  │
│  │    - Manual approval required │  │
│  │    - Integration tests        │  │
│  │    - Health checks            │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 3. Deploy to Production       │  │
│  │    - 2 reviewer approval      │  │
│  │    - Pre-deployment checks    │  │
│  │    - Deployment               │  │
│  │    - Post-deployment tests    │  │
│  │    - Health verification      │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 4. Drift Detection            │  │
│  │    - Detect configuration     │  │
│  │    - Create issue if found    │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## GitHub Actions Workflows

### 1. Terraform CI (`terraform-ci.yml`)

**Trigger**: Pull requests, pushes to develop/feature branches

**Jobs**:
- Code quality and formatting
- Security scanning (Trivy, Checkov, tfsec)
- Terraform validation
- Infrastructure planning
- Cost estimation
- Dependency scanning
- SAST (CodeQL)

**Outputs**:
- PR comments with plan summary
- Security scan results in Security tab
- Cost estimates
- Validation status

### 2. Terraform CD (`terraform-cd.yml`)

**Trigger**: Merge to main/master, workflow_dispatch

**Jobs**:
- Security and compliance scan
- Code quality and linting
- Component validation (dev, staging, prod)
- Infrastructure planning (all environments)
- Deploy to dev (automatic)
- Deploy to staging (manual approval)
- Deploy to production (2 reviewers required)
- Drift detection
- Notifications

**Features**:
- Automatic deployment to dev
- Manual approval gates for staging/prod
- Health checks after each deployment
- Rollback on failure
- Slack notifications

### 3. Security Scan (`security-scan.yml`)

**Trigger**: Daily at 2 AM UTC, workflow_dispatch

**Jobs**:
- Comprehensive security scanning
- AWS GuardDuty findings check
- AWS Security Hub compliance
- Python dependency vulnerabilities
- Secrets detection
- License compliance

**Outputs**:
- Security scan reports (90-day retention)
- GitHub Security tab alerts
- Automated issues for critical findings

### 4. Drift Detection (`drift-detection.yml`)

**Trigger**: Hourly, workflow_dispatch

**Jobs**:
- Detect configuration drift per environment
- Generate drift reports
- Create/update GitHub issues
- Alert team on drift

**Features**:
- Multi-environment support
- Automatic issue creation
- Drift report artifacts

## Pre-commit Hooks

Installed via `.pre-commit-config.yaml`:

```bash
# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files

# Update hooks
pre-commit autoupdate
```

**Hooks**:
- Terraform format (`terraform fmt`)
- Terraform validate
- TFLint
- Checkov security scan
- Secret detection
- Python formatting (Black, isort)
- Python linting (flake8)
- Python security (Bandit)
- Shell script linting (shellcheck)
- YAML linting
- Markdown linting

## Testing Framework

### Integration Tests

Location: `/tests/integration/`

```bash
# Run integration tests
pytest tests/integration/ -v

# Run with coverage
pytest tests/integration/ --cov=components --cov-report=html
```

Tests:
- `test_vpc_connectivity.py` - VPC, subnets, routing
- `test_security_groups.py` - Security group configuration
- `test_rds_connection.py` - Database connectivity
- `test_eks_cluster.py` - Kubernetes cluster health

### Smoke Tests

Location: `/tests/smoke/`

```bash
# Run smoke tests
./tests/smoke/test_endpoints.sh
./tests/smoke/test_health_checks.sh
```

Tests:
- Endpoint availability
- Health checks
- Service readiness
- Basic connectivity

### Security Tests

Location: `/tests/security/`

Tests:
- IAM policy validation
- Security group rules
- Encryption configuration
- Compliance checks

## Deployment Automation

### Bootstrap Script

Initialize infrastructure prerequisites:

```bash
./scripts/bootstrap.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --region us-east-1
```

Creates:
- S3 backend bucket (encrypted, versioned)
- DynamoDB locks table
- VPC endpoints (optional)
- Terraform state initialization

### Deployment Script

Automated deployment with health checks:

```bash
# Deploy all components
./scripts/deploy.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01

# Deploy specific components
./scripts/deploy.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --components vpc,securitygroup,iam

# Auto-approve (CI/CD)
./scripts/deploy.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --auto-approve
```

Features:
- Component dependency ordering
- Health checks after each component
- Automatic rollback on failure
- Smoke test execution
- Deployment summary

### Rollback Script

```bash
./scripts/rollback.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --target-version v1.2.3
```

### Destroy Script

```bash
./scripts/destroy.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01
```

## Docker Development Environment

Pre-configured container with all tools:

```bash
# Build image
docker-compose -f docker-compose.devops.yml build

# Start container
docker-compose -f docker-compose.devops.yml up -d

# Access shell
docker-compose -f docker-compose.devops.yml exec devops bash

# Stop container
docker-compose -f docker-compose.devops.yml down
```

**Included Tools**:
- Terraform 1.5.7
- Atmos 1.44.0
- AWS CLI v2
- kubectl 1.28.0
- Helm 3.13.0
- tflint, tfsec, checkov
- Python 3.11 + tools
- Trivy, Infracost

## Makefile Enhancements

New targets for CI/CD:

```bash
# Install prerequisites
make install

# Bootstrap environment
make bootstrap

# Validate all
make validate-all

# Deploy to dev
make deploy-dev

# Deploy to staging
make deploy-staging

# Deploy to production
make deploy-prod

# Run tests
make test
make smoke-test
make integration-test

# Security scanning
make security-scan

# Cost estimation
make cost-estimate

# Clean artifacts
make clean
```

## Environment Configuration

### Required GitHub Secrets

```yaml
# AWS Credentials
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ROLE_ARN_DEV
AWS_ROLE_ARN_STAGING
AWS_ROLE_ARN_PROD

# Notifications
SLACK_WEBHOOK_URL

# Cost Estimation
INFRACOST_API_KEY

# Code Analysis
SONAR_TOKEN
```

### Environment Protection Rules

**Dev**:
- No approval required
- Auto-deploy on merge to main

**Staging**:
- 1 reviewer approval required
- Manual deployment trigger

**Production**:
- 2 reviewers approval required
- Manual deployment trigger
- Deployment branch: main/master only

## Monitoring and Observability

### CI/CD Metrics

Tracked automatically:
- Deployment frequency
- Lead time for changes
- Mean time to recovery (MTTR)
- Change failure rate
- Build duration
- Test coverage
- Security scan results

### Dashboards

Available in GitHub Actions:
- Workflow runs history
- Success/failure rates
- Duration trends
- Security findings

### Notifications

Slack notifications for:
- Deployment success/failure
- Security scan results
- Drift detection
- Failed smoke tests

## Best Practices

### For Developers

1. Always create feature branches
2. Run pre-commit hooks before pushing
3. Write tests for infrastructure changes
4. Keep PRs focused and small
5. Review security scan results
6. Test locally with Docker container

### For Operations

1. Monitor drift detection alerts
2. Review daily security scans
3. Keep track of deployment metrics
4. Maintain environment protection rules
5. Regular backup validation
6. Update tool versions regularly

## Troubleshooting

### CI Pipeline Failures

```bash
# Check workflow logs
gh run view <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed

# Check security findings
gh api /repos/{owner}/{repo}/code-scanning/alerts
```

### Deployment Failures

```bash
# Check Terraform state
atmos terraform state list -s <stack>

# View component outputs
atmos terraform output <component> -s <stack>

# Check logs
cat logs/*.log
```

### Drift Detection Issues

```bash
# Manual drift check
atmos workflow drift-detection \
  tenant=fnx account=dev environment=testenv-01

# View drift report
cat drift-reports/*.txt
```

## Maintenance

### Weekly Tasks

- Review security scan reports
- Check drift detection issues
- Update dependencies
- Review cost estimates

### Monthly Tasks

- Update tool versions
- Review and optimize workflows
- Update documentation
- Audit access controls

### Quarterly Tasks

- Disaster recovery testing
- Performance optimization
- Security audit
- Compliance review

## Support

- Documentation: `/docs/`
- Examples: `/examples/`
- Issues: GitHub Issues
- CI/CD Questions: DevOps Team

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Atmos Documentation](https://atmos.tools/)
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
