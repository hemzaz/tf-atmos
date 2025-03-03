# 🔒 Git Branching Strategy for Terraform-Atmos

_Last Updated: March 3, 2025_

## 🎯 Goals & Requirements

When managing infrastructure-as-code, a robust git branching strategy must:

1. **🛡️ Protect Production**: Prevent accidental changes to production environments
2. **🔄 Enable Continuous Development**: Allow multiple developers to work simultaneously
3. **👁️ Ensure Visibility**: Make changes traceable and reviewable
4. **⚡ Support Fast Iteration**: Enable quick fixes without bureaucracy
5. **🧪 Facilitate Testing**: Ensure changes are validated before reaching production
6. **🔁 Support CI/CD**: Integrate with automated testing and deployment pipelines

## 🏗️ Recommended Strategy: GitFlow with Environment Protection

We recommend a modified GitFlow approach specifically tailored for infrastructure management with strong environment protection guardrails.

### 🌳 Branch Structure

```
┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │
│    master       │────▶│   production    │
│    (main)       │     │                 │
│                 │     │                 │
└────────┬────────┘     └─────────────────┘
         │                      ▲
         │                      │
         ▼                      │
┌─────────────────┐     ┌───────┴─────────┐
│                 │     │                 │
│  development    │────▶│    staging      │
│                 │     │                 │
│                 │     │                 │
└────────┬────────┘     └─────────────────┘
         │                      ▲
         │                      │
┌────────┼────────┐     ┌───────┴─────────┐
│        │        │     │                 │
▼        ▼        ▼     │     qa          │
feature/  fix/    env/  │                 │
branches branches branches                │
                        └─────────────────┘
```

### 🔑 Key Branches

1. **🔒 Production Branch (`production`)**
   - Direct representation of production environment
   - Protected - changes only via approved PRs
   - Tagged with releases
   - **No direct commits allowed**

2. **⭐ Master Branch (`master` or `main`)**
   - Represents the next production release
   - Protected - changes only via approved PRs
   - **No direct commits allowed**
   - All code here has passed all tests

3. **🧩 Development Branch (`development`)**
   - Integration branch for features
   - Deployed to development environments
   - Semi-protected - changes via PRs recommended

4. **🏁 Environment Branches (`staging`, `qa`)**
   - Long-lived branches for specific environments
   - Created from development/master
   - Deployed to their respective environments
   - Changes flow upward through environments

5. **🛠️ Feature Branches (`feature/*`)**
   - Short-lived branches for new components/features
   - Created from development
   - Merged back to development via PR
   - Naming: `feature/eks-autoscaling`, `feature/cert-manager`

6. **🔧 Fix Branches (`fix/*`)**
   - Short-lived branches for bug fixes
   - Created from development or master (for hotfixes)
   - Merged back via PR
   - Naming: `fix/vpc-endpoint-issue`, `fix/eks-iam-role`

7. **🌐 Environment-Specific Branches (`env/*`)**
   - For environment-specific configurations
   - Naming: `env/dev-02-customization`, `env/staging-vpc-update`

## 🔄 Workflow Processes

### 🚀 Feature Development Process

1. Create feature branch from development
   ```bash
   git checkout development
   git pull
   git checkout -b feature/new-component
   ```

2. Develop and test locally
   ```bash
   # Make changes
   # Test with local atmos apply/plan
   ```

3. Push branch and create PR to development
   ```bash
   git push -u origin feature/new-component
   # Open PR via GitHub UI or gh CLI
   ```

4. Automated tests and reviews
   - CI runs `atmos workflow validate`
   - CI runs `atmos workflow plan-environment`
   - Peer reviews required
   - Branch protection ensures all checks pass

5. Merge to development (squash merge recommended)
   - Development environments updated automatically

### 🔥 Hotfix Process

1. Create hotfix branch from master
   ```bash
   git checkout master
   git pull
   git checkout -b fix/critical-issue
   ```

2. Make minimal targeted changes
   ```bash
   # Make only necessary changes
   # Test thoroughly
   ```

3. Open PR to master with detailed explanation
   - Extra reviewers required
   - Deploy tests to staging required

4. After approval, merge to master
   - Ensure changes are also applied to development
   ```bash
   git checkout development
   git pull
   git merge origin/master
   git push
   ```

### 🚢 Release Process

1. Create release branch from development
   ```bash
   git checkout development
   git pull
   git checkout -b release/v1.2.0
   ```

2. Final testing and adjustments
   ```bash
   # Final version adjustments
   # Last-minute fixes
   ```

3. Open PR to master
   - Complete QA sign-off required
   - Security review required
   - Documentation review required

4. After approval, merge to master (no squash)
   - Tag the master with version
   ```bash
   git tag -a v1.2.0 -m "Release v1.2.0"
   git push origin v1.2.0
   ```

5. Open PR from master to production
   - Final sign-off from operations team
   - Scheduled deployment window

## 🛡️ Protection Mechanisms

### 🔒 Branch Protection Rules

1. **Production Branch**
   - Require 3+ approving reviews
   - Require successful CI/CD pipeline
   - Require specific approvers (Ops/SRE team)
   - Block force pushes
   - Block deletion
   - Require signed commits
   - Require linear history
   - Require deployment to staging for 48+ hours

2. **Master Branch**
   - Require 2+ approving reviews
   - Require successful CI/CD pipeline
   - Block force pushes
   - Block deletion
   - Require signed commits
   - Require linear history

3. **Development Branch**
   - Require 1+ approving reviews
   - Require successful CI/CD pipeline
   - Block force pushes
   - Allow administrators to bypass

### 🧪 Automated Testing

1. **Pre-commit Hooks**
   - Terraform format validation
   - YAML linting
   - Secret detection
   - Policy checking (OPA/Conftest)

2. **CI Pipeline Checks**
   - `atmos workflow validate`
   - `atmos workflow lint`
   - `atmos workflow plan-environment`
   - Automated testing of components

3. **Drift Detection**
   - Regular drift detection in environments
   - Automated PRs for reconciliation

## 🤝 Pull Request Workflows

### 📋 Required PR Template

```markdown
## Description
[Description of the changes]

## Type of change
- [ ] New feature (non-breaking)
- [ ] Enhancement (non-breaking)
- [ ] Bug fix (non-breaking)
- [ ] Breaking change

## Affected Components
- [ ] VPC
- [ ] EKS
- [ ] IAM
- [ ] Monitoring
- [List other components...]

## Affected Environments
- [ ] Development
- [ ] QA
- [ ] Staging
- [ ] Production

## Validation Steps
- [ ] `atmos workflow validate` passing
- [ ] `atmos workflow plan-environment` shows expected changes
- [ ] Local testing completed
- [ ] Documentation updated

## Deployment Impact
- [ ] Zero downtime
- [ ] Brief service interruption
- [ ] Requires maintenance window
- [ ] Requires database migration
- [ ] Requires manual verification

## Security Review
- [ ] Sensitive resources changed (Y/N)
- [ ] IAM changes (Y/N)
- [ ] Network security changes (Y/N)
```

### 👁️ Review Requirements

1. **Code Review**
   - Terraform best practices
   - Component integration checks
   - Variable/parameter verification

2. **Architecture Review** (for major changes)
   - Design validation
   - Performance impact assessment
   - Cost implications

3. **Security Review** (for security-related changes)
   - IAM policy review
   - Network security validation
   - Secret handling validation

## 🎛️ Operations Integration

### 🔄 CI/CD Integration

1. **Environment Updates**
   - Development environment: Automatic deployment from development branch
   - QA environment: Automatic deployment from qa branch
   - Staging environment: Approved deployment from staging branch
   - Production environment: Scheduled deployment from production branch

2. **Pre-Deployment Checks**
   - Drift detection
   - State validation
   - Cost estimate

3. **Post-Deployment Verification**
   - Smoke tests
   - Alert monitoring
   - Rollback readiness

### 🚨 Emergency Process

1. **Break-Glass Procedure**
   - Documented emergency access process
   - Requires multi-person authorization
   - Full audit logging
   - Post-incident reconciliation

2. **Rollback Capabilities**
   - Every production change has defined rollback plan
   - Automated rollback scripts where possible
   - Regular rollback testing

## 🧠 Developer Experience

### 🛠️ Tooling Support

1. **Visual Studio Code Integration**
   - Branch visualization extension
   - PR templates
   - Commit templates

2. **CLI Workflow Helpers**
   ```bash
   # Create feature branch
   atmos dev start-feature component-name
   
   # Create fix branch
   atmos dev start-fix issue-name
   
   # Open PR for current branch
   atmos dev create-pr
   ```

3. **Documentation**
   - Branch strategy visualization
   - Decision tree for branch selection
   - Example workflows for common scenarios

## 📊 Case Studies & Examples

### 🔍 Example: Adding a New Component

```bash
# Start from development
git checkout development
git pull

# Create feature branch
git checkout -b feature/new-monitoring-dashboard

# Develop and test component
mkdir -p components/terraform/new-dashboard
# Create component files
atmos terraform validate new-dashboard -s dev-account-testenv

# Commit changes
git add .
git commit -m "Add new monitoring dashboard component"

# Push and create PR
git push -u origin feature/new-monitoring-dashboard
gh pr create --base development --title "Add new monitoring dashboard"
```

After PR approval and merging:
```bash
# Deployed automatically to development environment

# For specific customization of staging
git checkout staging
git pull
git checkout -b env/staging-dashboard-customization
# Make staging-specific changes
git push -u origin env/staging-dashboard-customization
gh pr create --base staging
```

### 🔍 Example: Emergency Production Fix

```bash
# Start from production
git checkout production
git pull

# Create hotfix branch
git checkout -b fix/critical-security-issue

# Make minimal, focused changes
# Test thoroughly

# Push and create PR
git push -u origin fix/critical-security-issue
gh pr create --base production --title "[URGENT] Fix critical security issue"
```

After emergency approval and merging:
```bash
# Backport to master and development
git checkout master
git pull
git merge origin/production
git push

git checkout development
git pull
git merge origin/master
git push
```

## 🔄 Migration Plan

If you're transitioning from a different branching strategy:

1. **Preparation Phase**
   - Document current state
   - Create protection rules for new branches
   - Train team on new workflow

2. **Implementation Phase**
   - Create initial branch structure
   - Start using new feature branches
   - Begin enforcing PR requirements

3. **Optimization Phase**
   - Refine processes based on feedback
   - Enhance automation
   - Measure improvements in stability

## 🚦 Decision Flow Chart

```
Question: Where should I branch from?
├── Q: Is this an emergency fix needed in production?
│   ├── Yes → Branch from 'master'
│   └── No ─┐
│           ▼
├── Q: Is this a new feature or enhancement?
│   ├── Yes → Branch from 'development'
│   └── No ─┐
│           ▼
├── Q: Is this an environment-specific configuration?
│   ├── Yes → Branch from corresponding environment branch
│   └── No ─┐
│           ▼
└── Default → Ask team lead for guidance
```

## 📝 Conclusion

This git branching strategy provides strong protection for production environments while enabling developer agility. By clearly separating different types of changes and enforcing a progressive promotion path through environments, the risk of problematic changes reaching production is minimized.

Remember that the most critical elements are:

1. **🛡️ Protected production and master branches**
2. **👥 Mandatory peer reviews**
3. **🔄 Automated testing at each stage**
4. **📃 Clear documentation of changes via PRs**
5. **🚦 Structured promotion through environments**

By following this strategy, your team can maintain a high velocity of infrastructure changes while ensuring the stability and security of your production systems.