# Alexandria Library - Lifecycle Workflows

**Version:** 1.0.0
**Last Updated:** December 2, 2025

---

## Overview

This document defines the complete lifecycle workflows for Alexandria Library modules, from creation to archival. Each workflow includes automated checks, gates, and integration points with CI/CD systems.

---

## Table of Contents

1. [Module Creation Workflow](#module-creation-workflow)
2. [Module Publishing Workflow](#module-publishing-workflow)
3. [Module Versioning Workflow](#module-versioning-workflow)
4. [Module Testing Workflow](#module-testing-workflow)
5. [Module Promotion Workflow](#module-promotion-workflow)
6. [Module Deprecation Workflow](#module-deprecation-workflow)
7. [Module Archival Workflow](#module-archival-workflow)
8. [CI/CD Integration](#cicd-integration)
9. [Automated Quality Gates](#automated-quality-gates)

---

## Module Creation Workflow

### Overview

Creating a new module from scratch using scaffolding tools and templates.

### Workflow Diagram

```
┌─────────────┐
│   Ideation  │
└──────┬──────┘
       │
       v
┌─────────────────────┐
│ Run Scaffold Tool   │
│ alexandria scaffold │
└──────┬──────────────┘
       │
       v
┌──────────────────────────┐
│ Generate Module Structure│
│ - main.tf                │
│ - variables.tf           │
│ - outputs.tf             │
│ - README.md              │
│ - tests/                 │
│ - examples/              │
│ - .alexandria.yaml       │
└──────┬───────────────────┘
       │
       v
┌─────────────────────┐
│ Implement Resources │
│ Write Terraform code│
└──────┬──────────────┘
       │
       v
┌──────────────────┐
│ Write Tests      │
│ - Unit tests     │
│ - Integration    │
└──────┬───────────┘
       │
       v
┌──────────────────┐
│ Write Examples   │
│ - Basic example  │
│ - Complete       │
└──────┬───────────┘
       │
       v
┌──────────────────┐
│ Write Docs       │
│ - README.md      │
│ - Architecture   │
└──────┬───────────┘
       │
       v
┌──────────────────┐
│ Local Validation │
│ terraform fmt    │
│ terraform validate│
└──────┬───────────┘
       │
       v
┌──────────────────┐
│ Git Commit       │
│ Create branch    │
└──────┬───────────┘
       │
       v
┌──────────────────┐
│ Create PR        │
└──────────────────┘
```

### Commands

```bash
# Step 1: Scaffold new module
alexandria scaffold \
  --name vpc-enterprise \
  --category foundations/networking \
  --maturity experimental \
  --complexity advanced \
  --template vpc

# Step 2: Navigate to module directory
cd components/terraform/_library/foundations/networking/vpc-enterprise

# Step 3: Implement resources
# Edit main.tf, variables.tf, outputs.tf

# Step 4: Write tests
cd tests/unit
# Create test files

# Step 5: Write examples
cd ../../examples/complete
# Create example configuration

# Step 6: Write documentation
# Edit README.md

# Step 7: Validate locally
terraform fmt -recursive
terraform init
terraform validate

# Step 8: Run local tests
cd ../..
alexandria test . --unit

# Step 9: Commit and push
git checkout -b feature/vpc-enterprise
git add .
git commit -m "Add vpc-enterprise module"
git push origin feature/vpc-enterprise

# Step 10: Create pull request
gh pr create \
  --title "Add vpc-enterprise module" \
  --body "New VPC module for enterprise deployments"
```

### Automated Checks (Pre-commit)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: terraform-fmt
        name: Terraform Format
        entry: terraform fmt -recursive -check
        language: system
        pass_filenames: false

      - id: terraform-validate
        name: Terraform Validate
        entry: terraform validate
        language: system
        pass_filenames: false

      - id: alexandria-validate
        name: Alexandria Validate
        entry: alexandria validate
        language: system
        pass_filenames: false

      - id: tflint
        name: TFLint
        entry: tflint
        language: system
        pass_filenames: false
```

---

## Module Publishing Workflow

### Overview

Publishing a module to make it available in the catalog.

### Workflow Diagram

```
┌──────────────────┐
│ Module Complete  │
└────────┬─────────┘
         │
         v
┌──────────────────────┐
│ Run Validation       │
│ alexandria validate  │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐     Fail
│ Validation Passes?   ├─────────> Fix Issues
└────────┬─────────────┘
         │ Pass
         v
┌──────────────────────┐
│ Run Test Suite       │
│ alexandria test      │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐     Fail
│ Tests Pass?          ├─────────> Fix Tests
└────────┬─────────────┘
         │ Pass
         v
┌──────────────────────┐
│ Run Security Scans   │
│ - checkov            │
│ - tfsec              │
│ - terrascan          │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐     Fail
│ Security OK?         ├─────────> Fix Vulns
└────────┬─────────────┘
         │ Pass
         v
┌──────────────────────┐
│ Generate Docs        │
│ terraform-docs       │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Register in Catalog  │
│ alexandria register  │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Create Git Tag       │
│ git tag v1.0.0       │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Update CHANGELOG.md  │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Publish Module       │
│ alexandria publish   │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Notify Team          │
│ Slack notification   │
└──────────────────────┘
```

### Commands

```bash
# Step 1: Validate module
alexandria validate /path/to/module
# Output: ✓ Structure validation passed
#         ✓ Naming conventions passed
#         ✓ Documentation complete
#         ✓ Tests present

# Step 2: Run tests
alexandria test /path/to/module
# Output: ✓ Unit tests: 15/15 passed
#         ✓ Integration tests: 5/5 passed
#         ✓ Coverage: 87%

# Step 3: Security scans
checkov -d /path/to/module
tfsec /path/to/module
terrascan scan -t terraform -d /path/to/module

# Step 4: Generate documentation
terraform-docs markdown /path/to/module --output-file README.md

# Step 5: Register module
alexandria register /path/to/module \
  --version 1.0.0 \
  --maturity alpha \
  --tags "vpc,networking,multi-az"

# Output: ✓ Module registered successfully
#         Module ID: vpc-enterprise
#         Version: 1.0.0
#         Catalog entry created

# Step 6: Create git tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# Step 7: Update changelog
cat >> CHANGELOG.md <<EOF
## [1.0.0] - $(date +%Y-%m-%d)

### Added
- Initial release
- Multi-AZ VPC support
- Transit Gateway integration

EOF

# Step 8: Publish module
alexandria publish vpc-enterprise \
  --version 1.0.0 \
  --notes "Initial release with Transit Gateway support"

# Output: ✓ Module published successfully
#         ✓ Catalog updated
#         ✓ Search index updated
#         ✓ Documentation generated
```

### CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/publish-module.yml
name: Publish Module

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0

      - name: Install Alexandria CLI
        run: |
          pip install alexandria-cli

      - name: Extract version
        id: version
        run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_OUTPUT

      - name: Validate module
        run: |
          alexandria validate .

      - name: Run tests
        run: |
          alexandria test . --unit --integration

      - name: Security scans
        run: |
          checkov -d .
          tfsec .
          terrascan scan -t terraform -d .

      - name: Generate docs
        run: |
          terraform-docs markdown . --output-file README.md

      - name: Register module
        run: |
          alexandria register . \
            --version ${{ steps.version.outputs.VERSION }} \
            --maturity alpha

      - name: Publish module
        run: |
          alexandria publish $(basename $PWD) \
            --version ${{ steps.version.outputs.VERSION }}

      - name: Notify Slack
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "New module published: $(basename $PWD) v${{ steps.version.outputs.VERSION }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## Module Versioning Workflow

### Overview

Bumping module version following semantic versioning.

### Workflow Diagram

```
┌─────────────────┐
│ Code Changes    │
└────────┬────────┘
         │
         v
┌──────────────────────┐
│ Determine Version    │
│ Major? Minor? Patch? │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Update Version       │
│ .alexandria.yaml     │
│ versions.tf          │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Update CHANGELOG.md  │
│ Document changes     │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Run Full Test Suite  │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐     Fail
│ Tests Pass?          ├─────────> Fix Issues
└────────┬─────────────┘
         │ Pass
         v
┌──────────────────────┐
│ Create Git Tag       │
│ git tag vX.Y.Z       │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Update Registry      │
│ alexandria register  │
└────────┬─────────────┘
         │
         v
┌──────────────────────┐
│ Publish New Version  │
└──────────────────────┘
```

### Semantic Versioning Decision Tree

```
Did you change the API in a backward-incompatible way?
├─ YES → MAJOR version bump (1.0.0 → 2.0.0)
│   Examples:
│   - Removed variable
│   - Changed variable type
│   - Removed output
│   - Changed default behavior (breaking)
│   - Removed resource
│
└─ NO → Did you add new functionality?
    ├─ YES → MINOR version bump (1.0.0 → 1.1.0)
    │   Examples:
    │   - Added new variable (with default)
    │   - Added new output
    │   - Added new optional resource
    │   - Added new feature (opt-in)
    │
    └─ NO → PATCH version bump (1.0.0 → 1.0.1)
        Examples:
        - Fixed bug
        - Updated documentation
        - Performance improvement (no behavior change)
        - Updated dependencies (compatible)
```

### Commands

```bash
# Automated version bump
alexandria version vpc-standard \
  --bump minor \
  --changelog "Added IPv6 support and Transit Gateway integration"

# Manual process

# Step 1: Update .alexandria.yaml
vim .alexandria.yaml
# Change: version: "1.0.0" → "1.1.0"

# Step 2: Update versions.tf if needed
vim versions.tf

# Step 3: Update CHANGELOG.md
vim CHANGELOG.md
# Add entry:
# ## [1.1.0] - 2025-12-02
# ### Added
# - IPv6 support
# - Transit Gateway integration

# Step 4: Run tests
alexandria test . --all

# Step 5: Commit changes
git add .
git commit -m "Bump version to 1.1.0: Add IPv6 and Transit Gateway support"

# Step 6: Create tag
git tag -a v1.1.0 -m "Version 1.1.0: IPv6 and Transit Gateway support"
git push origin v1.1.0

# Step 7: Register new version
alexandria register . --version 1.1.0

# Step 8: Publish
alexandria publish vpc-standard --version 1.1.0
```

---

## Module Testing Workflow

### Overview

Comprehensive testing strategy for modules.

### Test Pyramid

```
              ┌──────────────────┐
              │   E2E Tests      │  Small number
              │   (Slow, Full)   │  High confidence
              └──────────────────┘
                      ▲
                      │
            ┌─────────────────────┐
            │ Integration Tests   │  Moderate number
            │ (Medium, Real AWS)  │  Good confidence
            └─────────────────────┘
                      ▲
                      │
        ┌────────────────────────────┐
        │      Unit Tests            │  Large number
        │   (Fast, Mocked)           │  Basic confidence
        └────────────────────────────┘
```

### Test Types

#### 1. Unit Tests

**Purpose:** Test individual resource configurations, variable validation, local calculations.

**Tools:** Terraform test, Terratest

**Example:**
```hcl
# tests/unit/vpc_cidr_validation.tftest.hcl
run "valid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/16"
  }

  assert {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be valid"
  }
}

run "invalid_vpc_cidr_too_large" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/12"
  }

  expect_failures = [var.vpc_cidr]
}
```

#### 2. Integration Tests

**Purpose:** Test actual resource creation in AWS, resource relationships.

**Tools:** Terratest, kitchen-terraform

**Example:**
```go
// tests/integration/vpc_test.go
func TestVPCCreation(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../../examples/complete",
        Vars: map[string]interface{}{
            "vpc_cidr": "10.0.0.0/16",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)

    // Validate VPC in AWS
    vpc := aws.GetVpcById(t, vpcID, "us-east-1")
    assert.Equal(t, "10.0.0.0/16", vpc.CidrBlock)
}
```

#### 3. End-to-End Tests

**Purpose:** Test complete workflows, multi-module stacks.

**Tools:** Terratest, custom scripts

**Example:**
```go
// tests/e2e/full_stack_test.go
func TestFullStackDeployment(t *testing.T) {
    // Deploy VPC
    vpcOptions := &terraform.Options{...}
    terraform.InitAndApply(t, vpcOptions)

    // Deploy EKS (depends on VPC)
    eksOptions := &terraform.Options{
        Vars: map[string]interface{}{
            "vpc_id": terraform.Output(t, vpcOptions, "vpc_id"),
        },
    }
    terraform.InitAndApply(t, eksOptions)

    // Validate end-to-end functionality
    // ...
}
```

### Test Workflow

```yaml
# .github/workflows/test-module.yml
name: Test Module

on:
  pull_request:
    paths:
      - 'components/terraform/**'

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2

      - name: Run unit tests
        run: |
          cd ${{ github.event.pull_request.changed_files[0] }}
          terraform test

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    if: github.event.pull_request.draft == false

    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_TEST_ROLE }}
          aws-region: us-east-1

      - name: Run integration tests
        run: |
          cd tests/integration
          go test -v -timeout 30m

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: components/terraform/
          framework: terraform

      - name: Run tfsec
        uses: aquasecurity/tfsec-action@v1.0.0
        with:
          working_directory: components/terraform/
```

---

## Module Promotion Workflow

### Overview

Promoting modules through maturity levels based on quality gates.

### Maturity Levels

```
Experimental → Alpha → Beta → Stable → Mature
```

### Promotion Criteria

#### Experimental → Alpha

```yaml
criteria:
  - basic_functionality: true
  - readme_exists: true
  - unit_tests_present: true
  - terraform_validate: passing

automated_checks:
  - terraform validate
  - terraform fmt -check
  - README.md exists
  - Unit tests directory exists

manual_review: false
approval_required: false
```

#### Alpha → Beta

```yaml
criteria:
  - all_features_implemented: true
  - api_design_complete: true
  - integration_tests: present
  - examples: >= 2
  - documentation: complete
  - security_scans: passing
  - time_in_alpha: >= 7 days

automated_checks:
  - All Alpha checks
  - Integration tests passing
  - Checkov passing
  - tfsec passing
  - Terrascan passing
  - Example count >= 2
  - Coverage >= 70%

manual_review: true
approval_required: 1 approver
```

#### Beta → Stable

```yaml
criteria:
  - time_in_beta: >= 30 days
  - zero_critical_bugs: true
  - test_coverage: >= 80%
  - production_usage: >= 3 teams
  - performance_benchmarks: met
  - security_review: complete
  - cost_validation: complete
  - migration_guide: exists (if applicable)

automated_checks:
  - All Beta checks
  - Coverage >= 80%
  - Zero critical bugs in last 30 days
  - Performance benchmarks met
  - No security vulnerabilities

manual_review: true
approval_required: 2 approvers (1 senior engineer)
```

#### Stable → Mature

```yaml
criteria:
  - time_in_stable: >= 180 days
  - zero_critical_bugs: last 90 days
  - performance_optimized: true
  - case_studies: >= 2
  - community_usage: active
  - test_coverage: >= 90%

automated_checks:
  - All Stable checks
  - Coverage >= 90%
  - Zero critical bugs in last 90 days
  - High community ratings (>= 4.5)

manual_review: true
approval_required: 2 approvers (1 architect)
```

### Commands

```bash
# Request promotion
alexandria promote vpc-standard \
  --from beta \
  --to stable \
  --justification "30 days in beta, 87% test coverage, 5 production teams using"

# Check promotion eligibility
alexandria promote-check vpc-standard --target stable

# Output:
# ✓ Time in beta: 45 days (required: 30)
# ✓ Critical bugs: 0 (required: 0)
# ✓ Test coverage: 87% (required: 80%)
# ✓ Production usage: 5 teams (required: 3)
# ✓ Security scans: All passing
# ✓ Performance benchmarks: Met
# ⚠ Migration guide: Not required (no breaking changes)
#
# Eligible for promotion to stable
# Required approvals: 2 (0 received)
```

---

## Module Deprecation Workflow

### Overview

Marking modules as deprecated and providing migration paths.

### Workflow

```
┌───────────────────┐
│ Deprecation       │
│ Decision Made     │
└─────────┬─────────┘
          │
          v
┌───────────────────────┐
│ Identify Replacement  │
│ or Migration Path     │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Create Migration      │
│ Guide                 │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Update Module         │
│ - .alexandria.yaml    │
│ - README.md           │
│ - Add warnings        │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Update Catalog        │
│ Mark as deprecated    │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Notify Users          │
│ - Email               │
│ - Slack               │
│ - Dashboard           │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Support Period        │
│ (90-180 days)         │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Final Warning         │
│ (30 days before)      │
└─────────┬─────────────┘
          │
          v
┌───────────────────────┐
│ Archive Module        │
└───────────────────────┘
```

### Commands

```bash
# Deprecate module
alexandria deprecate old-vpc \
  --replacement vpc-standard \
  --reason "Superseded by vpc-standard with better features" \
  --removal-date 2026-06-01 \
  --support-until 2026-03-01

# Generate migration guide
alexandria generate-migration-guide \
  --from old-vpc \
  --to vpc-standard \
  --output docs/migration-old-vpc-to-vpc-standard.md

# Send notifications
alexandria notify-deprecation old-vpc \
  --channels email,slack \
  --target-users all-users

# Check deprecation status
alexandria deprecation-status old-vpc

# Output:
# Module: old-vpc
# Status: Deprecated
# Replacement: vpc-standard
# Support until: 2026-03-01
# Removal date: 2026-06-01
# Active deployments: 45
# Migration guide: docs/migration-old-vpc-to-vpc-standard.md
```

### Deprecation Notice in README

```markdown
# Old VPC Module

> ⚠️ **DEPRECATED**
>
> This module is deprecated and will be removed on **June 1, 2026**.
>
> **Replacement:** [vpc-standard](../vpc-standard)
>
> **Migration Guide:** [Migration from old-vpc to vpc-standard](docs/migration.md)
>
> **Support:** Limited support until March 1, 2026
>
> Please migrate to `vpc-standard` for continued support and new features.
```

---

## Module Archival Workflow

### Overview

Moving deprecated modules to archived state.

### Workflow

```bash
# Archive module
alexandria archive old-vpc \
  --backup-location s3://alexandria-archives/modules/ \
  --keep-readonly

# Archive creates:
# 1. Backup in S3
# 2. Git tag: archived/old-vpc-v1.2.3
# 3. Moves to _archived/ directory
# 4. Updates catalog with archived status
# 5. Makes module read-only

# Archived module structure:
components/terraform/_archived/old-vpc/
├── ARCHIVED.md              # Archival notice
├── [original files]         # Original module files (read-only)
└── .git-attributes          # Force read-only
```

---

## CI/CD Integration

### GitHub Actions Workflows

#### 1. PR Validation

```yaml
# .github/workflows/pr-validation.yml
name: PR Validation

on:
  pull_request:
    paths:
      - 'components/terraform/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2

      - name: Terraform Format
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: |
          terraform init
          terraform validate

      - name: Alexandria Validate
        run: alexandria validate .

      - name: Security Scan
        run: |
          checkov -d .
          tfsec .

      - name: Unit Tests
        run: alexandria test . --unit
```

#### 2. Module Release

```yaml
# .github/workflows/release-module.yml
name: Release Module

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run full test suite
        run: alexandria test . --all

      - name: Publish module
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          alexandria publish $(basename $PWD) --version $VERSION

      - name: Create GitHub Release
        uses: actions/create-release@v1
        with:
          tag_name: ${{ github.ref }}
          release_name: Release ${{ github.ref }}
          draft: false
          prerelease: false
```

---

## Automated Quality Gates

### Quality Gate Configuration

```yaml
# quality-gates.yaml

gates:
  experimental_to_alpha:
    required_checks:
      - terraform_validate
      - terraform_fmt
      - readme_exists
      - unit_tests_present

    automated: true
    approval_required: false

  alpha_to_beta:
    required_checks:
      - all_experimental_checks
      - integration_tests_passing
      - security_scans_passing
      - coverage_minimum: 70
      - example_count: 2
      - documentation_complete

    automated: true
    approval_required: true
    approvers: 1

  beta_to_stable:
    required_checks:
      - all_beta_checks
      - time_in_beta_days: 30
      - coverage_minimum: 80
      - production_teams: 3
      - zero_critical_bugs: true
      - performance_benchmarks_met: true

    automated: false
    approval_required: true
    approvers: 2
    require_senior: true

  stable_to_mature:
    required_checks:
      - all_stable_checks
      - time_in_stable_days: 180
      - coverage_minimum: 90
      - community_rating: 4.5
      - case_studies: 2

    automated: false
    approval_required: true
    approvers: 2
    require_architect: true
```

---

## Best Practices

### 1. Version Tagging

```bash
# Always use annotated tags
git tag -a v1.0.0 -m "Release version 1.0.0"

# Include detailed release notes
git tag -a v1.0.0 -m "$(cat <<EOF
Release version 1.0.0

Features:
- Multi-AZ support
- IPv6 support
- Transit Gateway integration

Breaking Changes:
- Variable 'subnet_count' removed (use 'availability_zones' instead)

Migration:
See docs/migration-0.x-to-1.x.md
EOF
)"
```

### 2. Changelog Maintenance

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

## [1.1.0] - 2025-12-02

### Added
- IPv6 support (#123)
- Transit Gateway integration (#124)

### Changed
- Improved subnet CIDR calculation (#125)

### Deprecated
- Variable `subnet_count` (use `availability_zones` instead)

### Fixed
- NAT Gateway creation in single AZ mode (#126)

### Security
- Added encryption for flow logs (#127)
```

### 3. Testing Strategy

```bash
# Run tests locally before pushing
terraform fmt -recursive
terraform validate
alexandria test . --unit

# Run integration tests in feature branch
alexandria test . --integration

# Run full suite before release
alexandria test . --all --coverage
```

### 4. Documentation

```bash
# Auto-generate documentation
terraform-docs markdown . --output-file README.md

# Validate documentation
alexandria validate . --checks docs

# Generate architecture diagrams
terraform graph | dot -Tpng > docs/architecture.png
```

---

## Monitoring and Analytics

### Module Health Dashboard

Track key metrics for each module:

```yaml
metrics:
  quality:
    - test_coverage_percent
    - security_vulnerabilities
    - code_complexity
    - documentation_coverage

  usage:
    - active_deployments
    - downloads_per_week
    - unique_users

  reliability:
    - success_rate
    - failure_rate
    - mean_time_to_recovery

  performance:
    - deployment_time_avg
    - deployment_time_p95
    - resource_creation_time
```

### Alerts

```yaml
alerts:
  - name: high_failure_rate
    condition: failure_rate > 0.1
    severity: high
    action: notify_maintainer

  - name: security_vulnerability
    condition: vulnerabilities.critical > 0
    severity: critical
    action: block_promotion

  - name: low_test_coverage
    condition: coverage < 0.7
    severity: medium
    action: notify_maintainer
```

---

## Summary

These workflows provide a comprehensive lifecycle management system for Alexandria Library modules, ensuring quality, security, and maintainability throughout the module's lifetime.

**Key Takeaways:**

1. **Automated Quality Gates** - Consistent quality through automated checks
2. **Clear Promotion Path** - Well-defined maturity progression
3. **Comprehensive Testing** - Multi-layered testing strategy
4. **Semantic Versioning** - Predictable API evolution
5. **Graceful Deprecation** - Smooth migration paths
6. **CI/CD Integration** - Automated workflows reduce manual effort

**Next Steps:**

1. Implement scaffolding tool
2. Setup CI/CD pipelines
3. Create quality gate automation
4. Build monitoring dashboard
5. Train team on workflows
