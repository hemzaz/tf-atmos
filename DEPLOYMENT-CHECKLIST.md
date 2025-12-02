# CI/CD Deployment Checklist

Use this checklist to deploy the CI/CD pipeline.

## Pre-Deployment

- [ ] Review all documentation
- [ ] Verify team has required access
- [ ] Backup existing configurations
- [ ] Plan rollback strategy

## GitHub Configuration (30 minutes)

### Repository Secrets
- [ ] `AWS_ACCESS_KEY_ID`
- [ ] `AWS_SECRET_ACCESS_KEY`
- [ ] `AWS_ROLE_ARN_DEV`
- [ ] `AWS_ROLE_ARN_STAGING`
- [ ] `AWS_ROLE_ARN_PROD`
- [ ] `SLACK_WEBHOOK_URL`
- [ ] `INFRACOST_API_KEY`

### Environment Protection
- [ ] Create `dev` environment (no protection)
- [ ] Create `staging` environment (1 reviewer)
- [ ] Create `production` environment (2 reviewers)

### Branch Protection (main/master)
- [ ] Require PR reviews (1 approval)
- [ ] Require status checks
- [ ] Require up-to-date branches
- [ ] Include administrators
- [ ] Restrict force pushes

## Local Setup (15 minutes)

- [ ] Install pre-commit: `pip install pre-commit`
- [ ] Install hooks: `pre-commit install`
- [ ] Test hooks: `pre-commit run --all-files`
- [ ] Install testing dependencies: `pip install -r requirements-test.txt`

## Infrastructure Bootstrap (20 minutes)

- [ ] Review bootstrap script: `./scripts/bootstrap.sh --help`
- [ ] Bootstrap dev environment:
  ```bash
  ./scripts/bootstrap.sh \
    --tenant fnx \
    --account dev \
    --environment testenv-01 \
    --region us-east-1
  ```
- [ ] Verify S3 bucket created
- [ ] Verify DynamoDB table created
- [ ] Test Terraform state access

## Verification (15 minutes)

- [ ] Run verification script: `./scripts/verify-cicd-setup.sh`
- [ ] All critical checks pass
- [ ] Address any warnings
- [ ] Review verification report

## CI Pipeline Test (20 minutes)

- [ ] Create test branch: `git checkout -b test-ci`
- [ ] Make small change (add comment to README)
- [ ] Commit: `git commit -m "test: CI pipeline"`
- [ ] Push: `git push origin test-ci`
- [ ] Create pull request
- [ ] Wait for CI to complete
- [ ] Verify:
  - [ ] Code quality checks pass
  - [ ] Security scans complete
  - [ ] Validation succeeds
  - [ ] Plan is generated
  - [ ] Cost estimate appears
  - [ ] PR comments added

## CD Pipeline Test (30 minutes)

- [ ] Merge test PR
- [ ] Monitor CD workflow
- [ ] Verify dev deployment
- [ ] Check smoke tests pass
- [ ] Review deployment logs
- [ ] Verify infrastructure health

## Security Verification (15 minutes)

- [ ] Check Security tab for scan results
- [ ] Review any findings
- [ ] Verify daily scan scheduled
- [ ] Check drift detection scheduled

## Docker Environment (15 minutes)

- [ ] Build image: `docker-compose -f docker-compose.devops.yml build`
- [ ] Start container: `docker-compose -f docker-compose.devops.yml up -d`
- [ ] Access shell: `docker-compose -f docker-compose.devops.yml exec devops bash`
- [ ] Verify tools: `terraform --version && atmos version`
- [ ] Test Atmos commands
- [ ] Exit and stop: `docker-compose -f docker-compose.devops.yml down`

## Team Training (60 minutes)

- [ ] Share Quick Start Guide
- [ ] Walkthrough workflow process
- [ ] Demonstrate PR creation
- [ ] Show deployment process
- [ ] Explain approval process
- [ ] Demo pre-commit hooks
- [ ] Review documentation
- [ ] Q&A session

## Documentation Review (30 minutes)

- [ ] Quick Start Guide
- [ ] CI/CD README
- [ ] Implementation Summary
- [ ] Deliverables Index
- [ ] Team runbooks

## Post-Deployment

### Week 1
- [ ] Monitor all workflow runs
- [ ] Address any issues
- [ ] Gather team feedback
- [ ] Update documentation

### Week 2-4
- [ ] Add more tests
- [ ] Optimize workflows
- [ ] Fine-tune security scans
- [ ] Create team runbooks

### Month 2
- [ ] Review metrics
- [ ] Optimize costs
- [ ] Plan improvements
- [ ] Celebrate success!

## Rollback Plan

If issues occur:

1. Disable workflows temporarily:
   - Rename `.github/workflows/*.yml` to `*.yml.disabled`
2. Revert to previous process
3. Document issues
4. Fix and redeploy

## Success Metrics

After 1 week:
- [ ] 100% of PRs go through CI
- [ ] 0 security findings ignored
- [ ] < 5 failed deployments
- [ ] Team comfort level > 7/10

After 1 month:
- [ ] Deployment frequency daily
- [ ] Lead time < 2 hours
- [ ] MTTR < 30 minutes
- [ ] Change failure rate < 10%

## Support Contacts

- CI/CD Issues: DevOps Team
- Security: Security Team
- AWS Access: Cloud Ops
- Training: Platform Team

---

**Total Setup Time**: ~3-4 hours
**Ready for Production**: After all checks pass
