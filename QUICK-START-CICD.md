# CI/CD Quick Start Guide

Get your CI/CD pipeline up and running in 30 minutes.

## Prerequisites Checklist

- [ ] GitHub repository with admin access
- [ ] AWS account with credentials
- [ ] Terraform 1.5.7+ installed locally
- [ ] Atmos 1.44.0+ installed locally
- [ ] Python 3.11+ installed locally

## Step 1: Configure GitHub Repository (10 minutes)

### 1.1 Add Repository Secrets

Navigate to: **Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

```
AWS_ACCESS_KEY_ID=<your-aws-access-key>
AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>
AWS_ROLE_ARN_DEV=arn:aws:iam::ACCOUNT_ID:role/GitHubActions-Dev
AWS_ROLE_ARN_STAGING=arn:aws:iam::ACCOUNT_ID:role/GitHubActions-Staging
AWS_ROLE_ARN_PROD=arn:aws:iam::ACCOUNT_ID:role/GitHubActions-Prod
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
INFRACOST_API_KEY=<your-infracost-api-key>
```

### 1.2 Configure Environments

Navigate to: **Settings → Environments**

Create three environments:

**dev**:
- No protection rules
- Allow administrators to bypass rules

**staging**:
- Required reviewers: 1
- Allow administrators to bypass rules (optional)

**production**:
- Required reviewers: 2
- Deployment branches: main/master only
- Prevent administrators from bypassing (recommended)

### 1.3 Enable Branch Protection

Navigate to: **Settings → Branches → Add branch protection rule**

For `main` branch:
- [x] Require a pull request before merging
- [x] Require approvals (1)
- [x] Require status checks to pass
- [x] Require branches to be up to date
- [x] Include administrators
- [x] Restrict who can push to matching branches

## Step 2: Install Pre-commit Hooks (5 minutes)

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
cd /path/to/tf-atmos
pre-commit install

# Test hooks
pre-commit run --all-files
```

## Step 3: Bootstrap Infrastructure (10 minutes)

```bash
# Bootstrap dev environment
./scripts/bootstrap.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --region us-east-1

# Verify bootstrap
aws s3 ls | grep terraform-state
aws dynamodb list-tables | grep terraform-locks
```

## Step 4: Test CI Pipeline (5 minutes)

### 4.1 Create Test Branch

```bash
git checkout -b test-ci-pipeline
```

### 4.2 Make a Small Change

```bash
# Edit a file
echo "# Test CI" >> components/terraform/vpc/README.md

# Commit
git add .
git commit -m "test: Verify CI pipeline"

# Push
git push origin test-ci-pipeline
```

### 4.3 Create Pull Request

1. Go to GitHub repository
2. Click "Compare & pull request"
3. Review CI checks running
4. Wait for all checks to complete
5. Review PR comments (plan summary, security scan)

## Step 5: Verify CD Pipeline (Optional)

```bash
# Merge PR to trigger CD
# This will deploy to dev environment

# Watch deployment
gh run list --workflow=terraform-cd.yml

# View logs
gh run view <run-id>
```

## Common Commands

### Pre-commit
```bash
# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run terraform-fmt --all-files

# Update hooks
pre-commit autoupdate
```

### Testing
```bash
# Integration tests
pytest tests/integration/ -v

# Smoke tests
./tests/smoke/test_health_checks.sh

# All tests
make test
```

### Deployment
```bash
# Bootstrap
make bootstrap TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

# Validate
make validate

# Plan
make plan

# Deploy
make deploy-dev
```

### Docker Environment
```bash
# Start
docker-compose -f docker-compose.devops.yml up -d

# Shell access
docker-compose -f docker-compose.devops.yml exec devops bash

# Stop
docker-compose -f docker-compose.devops.yml down
```

### GitHub CLI
```bash
# View recent runs
gh run list --limit 10

# View specific run
gh run view <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed

# Trigger manual workflow
gh workflow run terraform-cd.yml \
  -f environment=dev \
  -f tenant=fnx \
  -f account=dev \
  -f action=plan
```

## Verification Checklist

After setup, verify:

- [ ] CI pipeline runs on PR creation
- [ ] Security scans complete successfully
- [ ] Terraform validation passes
- [ ] Plan is generated and commented on PR
- [ ] Cost estimation appears in PR
- [ ] Pre-commit hooks block bad commits
- [ ] CD pipeline triggers on merge
- [ ] Deployment to dev succeeds
- [ ] Smoke tests pass
- [ ] Drift detection runs hourly
- [ ] Daily security scans execute

## Troubleshooting

### CI Pipeline Not Running

**Problem**: Workflow doesn't trigger on PR

**Solution**:
1. Check workflow file syntax: `yamllint .github/workflows/terraform-ci.yml`
2. Verify file paths trigger: Check `paths:` in workflow
3. Check Actions tab for errors

### Authentication Failures

**Problem**: AWS authentication fails in workflow

**Solution**:
1. Verify secrets are set correctly
2. Check IAM role ARNs are correct
3. Verify role trust policy allows GitHub OIDC
4. Test credentials locally: `aws sts get-caller-identity`

### Pre-commit Hooks Failing

**Problem**: Hooks fail on commit

**Solution**:
```bash
# Update hooks
pre-commit autoupdate

# Skip hook temporarily
git commit --no-verify

# Fix specific issue
pre-commit run <hook-id> --all-files
```

### Deployment Failures

**Problem**: Terraform apply fails

**Solution**:
1. Check Terraform state: `atmos terraform state list -s <stack>`
2. View detailed logs in Actions tab
3. Run locally: `atmos terraform plan <component> -s <stack>`
4. Check for resource conflicts or quota limits

### Cost Estimation Not Showing

**Problem**: No cost estimates in PR

**Solution**:
1. Verify `INFRACOST_API_KEY` secret is set
2. Check Infracost service status
3. Verify component paths are correct

## Next Steps

Once basic setup is complete:

1. **Week 1**
   - [ ] Train team on new workflow
   - [ ] Run through deployment process
   - [ ] Document any custom procedures
   - [ ] Set up Slack notifications

2. **Week 2-4**
   - [ ] Add more integration tests
   - [ ] Fine-tune security scan rules
   - [ ] Optimize workflow performance
   - [ ] Create runbooks for common issues

3. **Month 2+**
   - [ ] Implement monitoring dashboards
   - [ ] Add performance testing
   - [ ] Review and optimize costs
   - [ ] Continuous improvement

## Resources

- [Complete Documentation](./CI-CD-README.md)
- [Implementation Summary](./DEVOPS-IMPLEMENTATION-SUMMARY.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Terraform Docs](https://www.terraform.io/docs)
- [Atmos Docs](https://atmos.tools)

## Support

- Documentation: `/docs/`
- Examples: `/examples/`
- Issues: Create GitHub issue
- Questions: Contact DevOps team

---

**Setup Time**: ~30 minutes
**Difficulty**: Intermediate
**Prerequisites**: AWS, GitHub, Terraform knowledge
