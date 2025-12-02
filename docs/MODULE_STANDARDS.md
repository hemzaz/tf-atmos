# Alexandria Library - Module Standards

**Version:** 1.0.0
**Last Updated:** December 2, 2025
**Status:** Active Standard

---

## Table of Contents

1. [Overview](#overview)
2. [Module Structure](#module-structure)
3. [Naming Conventions](#naming-conventions)
4. [Code Standards](#code-standards)
5. [Documentation Requirements](#documentation-requirements)
6. [Testing Requirements](#testing-requirements)
7. [Security Requirements](#security-requirements)
8. [Performance Standards](#performance-standards)
9. [Versioning Strategy](#versioning-strategy)
10. [Quality Gates](#quality-gates)

---

## Overview

These standards ensure consistency, quality, and maintainability across all modules in the Alexandria Library. All modules MUST comply with these standards before being accepted into the catalog.

### Compliance Levels

- **MUST:** Mandatory requirement
- **SHOULD:** Recommended practice
- **MAY:** Optional feature

---

## Module Structure

### Standard Directory Layout

Every module MUST follow this structure:

```
module-name/
├── .alexandria.yaml          # MUST: Module metadata
├── README.md                 # MUST: Module documentation
├── CHANGELOG.md              # MUST: Version history
├── LICENSE                   # MUST: License file
│
├── main.tf                   # MUST: Primary resources
├── variables.tf              # MUST: Input variables
├── outputs.tf                # MUST: Output values
├── provider.tf               # MUST: Provider configuration
├── locals.tf                 # SHOULD: Local values
├── data.tf                   # SHOULD: Data sources
├── versions.tf               # MUST: Version constraints
│
├── modules/                  # SHOULD: Submodules
│   └── submodule-name/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── examples/                 # MUST: Usage examples
│   ├── complete/            # MUST: Full-featured example
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── basic/               # SHOULD: Simple example
│   └── advanced/            # MAY: Complex scenario
│
├── tests/                    # MUST: Test suite
│   ├── unit/                # MUST: Unit tests
│   │   └── test_*.py
│   ├── integration/         # SHOULD: Integration tests
│   │   └── test_*.py
│   └── fixtures/            # Test data
│       └── *.tfvars
│
├── docs/                     # SHOULD: Additional documentation
│   ├── architecture.md
│   ├── migration.md
│   └── troubleshooting.md
│
└── templates/                # MAY: Template files
    └── *.tpl
```

### Module Metadata (.alexandria.yaml)

Every module MUST include a `.alexandria.yaml` file:

```yaml
# Required fields
module:
  id: "vpc-standard"                      # Unique identifier
  name: "Standard VPC"                    # Display name
  version: "1.2.3"                        # Semantic version
  maturity: "stable"                      # experimental|alpha|beta|stable|mature|deprecated

  # Classification
  category: "foundations/networking"      # Category path
  tags:                                   # Searchable tags
    - vpc
    - networking
    - multi-az
    - ipv6

  # Description
  description: "Production-ready VPC with 2-3 AZs, NAT, and VPC endpoints"
  long_description: |
    A comprehensive VPC module that creates a production-ready network
    infrastructure with multiple availability zones, NAT gateways,
    VPC endpoints, and complete subnet management.

  # Complexity
  complexity: "intermediate"              # beginner|intermediate|advanced
  setup_time_minutes: 15                  # Estimated deployment time
  variable_count: 25                      # Number of variables

  # Cost
  cost:
    estimated_monthly_usd: 150            # Estimated monthly cost
    cost_category: "medium"               # low|medium|high|very-high
    cost_factors:                         # What drives cost
      - "NAT Gateway count"
      - "VPC Endpoint count"
      - "Data transfer"

  # Ownership
  maintainer:
    team: "Platform Engineering"
    primary: "platform-team@example.com"
    backup: "sre-team@example.com"

  # Support
  support:
    channel: "#platform-support"
    sla: "24 hours"
    oncall: "platform-oncall"

  # Dependencies
  dependencies:
    terraform_version: ">= 1.5.0"
    provider_versions:
      aws: ">= 5.0.0, < 6.0.0"
    required_modules: []                  # Other modules needed

  # Compatibility
  compatible_with:
    - "eks-standard"
    - "rds-postgres"
    - "ecs-fargate"

  # Metrics
  metrics:
    downloads: 1250
    rating: 4.8
    deployments: 450
    last_updated: "2025-12-01"

  # Lifecycle
  lifecycle:
    created: "2024-01-15"
    stabilized: "2024-06-01"
    deprecated: null
    removed: null
    replacement: null

  # Documentation
  documentation:
    readme_url: "./README.md"
    examples:
      - path: "./examples/complete"
        description: "Full-featured VPC with all options"
      - path: "./examples/basic"
        description: "Simple VPC with minimal configuration"

  # Testing
  testing:
    unit_tests: 15
    integration_tests: 5
    coverage_percent: 85
    last_test_run: "2025-12-01T10:30:00Z"
    test_status: "passing"

  # Security
  security:
    checkov_passing: true
    tfsec_passing: true
    terrascan_passing: true
    last_scan: "2025-12-01"
    vulnerabilities: 0
```

---

## Naming Conventions

### Module Names

**Format:** `[complexity-]resource-type`

**Rules:**
- Use lowercase
- Use hyphens for word separation
- Include complexity prefix for variants: `basic-`, `standard-`, `advanced-`
- Use singular form
- Be descriptive but concise

**Examples:**
- ✓ `vpc-standard`
- ✓ `eks-fargate`
- ✓ `rds-postgres`
- ✗ `vpc_module` (use hyphens)
- ✗ `vpcs` (use singular)
- ✗ `module-1` (not descriptive)

### Resource Names

**Format:** `${local.name_prefix}-<resource-type>[-<descriptor>]`

```hcl
locals {
  name_prefix = "${var.tenant}-${var.environment}-${var.stage}"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  tags = {
    Name = "${local.name_prefix}-subnet-public-${var.availability_zones[count.index]}"
  }
}
```

### Variable Names

**Rules:**
- Use `snake_case`
- Be descriptive and explicit
- Use standard prefixes for booleans: `is_`, `has_`, `enable_`, `use_`
- Use plural for lists: `subnet_ids`, `availability_zones`
- Use singular for maps: `tag`, `label`

**Examples:**
```hcl
variable "vpc_cidr" {              # ✓ Good
  type = string
}

variable "enable_dns_support" {    # ✓ Good - boolean prefix
  type = bool
}

variable "availability_zones" {    # ✓ Good - plural list
  type = list(string)
}

variable "dns" {                   # ✗ Bad - not descriptive
  type = bool
}

variable "azs" {                   # ✗ Bad - use full words
  type = list(string)
}
```

### Output Names

**Rules:**
- Use `snake_case`
- Match resource attribute names when possible
- Be descriptive and explicit
- Group related outputs with prefixes

**Examples:**
```hcl
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}
```

---

## Code Standards

### Terraform Style

**MUST follow:**
- Use `terraform fmt` for consistent formatting
- Maximum line length: 120 characters
- Use 2 spaces for indentation
- One resource per block
- Alphabetize arguments within blocks (with exceptions for readability)

**Example:**
```hcl
resource "aws_vpc" "main" {
  assign_generated_ipv6_cidr_block     = var.enable_ipv6
  cidr_block                           = var.vpc_cidr
  enable_dns_hostnames                 = var.enable_dns_hostnames
  enable_dns_support                   = var.enable_dns_support
  enable_network_address_usage_metrics = var.enable_network_metrics
  instance_tenancy                     = var.instance_tenancy

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-vpc"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
```

### Variable Definitions

**MUST include:**
- Type constraint
- Description (detailed)
- Default value (when appropriate)
- Validation rules (when appropriate)

**Template:**
```hcl
variable "vpc_cidr" {
  type        = string
  description = <<-EOT
    The IPv4 CIDR block for the VPC. This must be a valid CIDR block between /16 and /28.
    Example: "10.0.0.0/16" provides 65,536 IP addresses.
    See: https://www.rfc-editor.org/rfc/rfc1918
  EOT
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block."
  }

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "The vpc_cidr must be between /16 and /28."
  }
}

variable "enable_dns_support" {
  type        = bool
  description = <<-EOT
    Enable DNS resolution in the VPC. When enabled, instances can resolve public DNS hostnames
    to IP addresses. This is required for most VPC endpoints and should generally remain enabled.
    Default: true
  EOT
  default     = true
}

variable "tags" {
  type        = map(string)
  description = <<-EOT
    Additional tags to apply to all resources. These tags will be merged with the default tags.
    Example:
      {
        Environment = "production"
        CostCenter  = "engineering"
      }
  EOT
  default     = {}
}
```

### Output Definitions

**MUST include:**
- Description
- Value
- Sensitive flag (when appropriate)

**Template:**
```hcl
output "vpc_id" {
  description = <<-EOT
    The ID of the VPC.
    Use this output to reference the VPC in other modules.
    Example: module.vpc.vpc_id
  EOT
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = <<-EOT
    List of private subnet IDs in availability zone order.
    Use these for resources that should not be directly accessible from the internet.
    Example: [subnet-abc123, subnet-def456, subnet-ghi789]
  EOT
  value       = aws_subnet.private[*].id
}

output "database_password" {
  description = "The master password for the database (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true
}
```

### Data Sources

**Group data sources in data.tf:**

```hcl
# data.tf

# Current AWS account
data "aws_caller_identity" "current" {}

# Current AWS region
data "aws_region" "current" {}

# Available availability zones
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# AMI lookup
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

### Local Values

**Use locals.tf for computed values:**

```hcl
# locals.tf

locals {
  # Naming
  name_prefix = "${var.tenant}-${var.environment}-${var.stage}"

  # Availability zones
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.max_availability_zones)
  az_count          = length(local.availability_zones)

  # CIDR calculations
  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  # Tags
  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      Module      = "vpc-standard"
      Environment = var.environment
      Tenant      = var.tenant
    }
  )
}
```

### Comments

**Use comments to explain WHY, not WHAT:**

```hcl
# ✓ Good - explains reasoning
# Using a /28 CIDR to minimize IP waste while maintaining
# sufficient addresses for future growth
variable "database_subnet_cidr_newbits" {
  type    = number
  default = 4  # /28 provides 16 IPs (11 usable)
}

# ✗ Bad - states the obvious
# This is the VPC CIDR variable
variable "vpc_cidr" {
  type = string
}

# ✓ Good - explains complex logic
# Calculate subnet CIDRs dynamically to ensure no overlaps
# Offset private subnets by 10, database subnets by 20
locals {
  private_subnet_cidrs = [
    for i in range(local.az_count) :
    cidrsubnet(var.vpc_cidr, 8, i + 10)  # +10 offset ensures no overlap with public subnets
  ]
}
```

---

## Documentation Requirements

### README.md Structure

Every module MUST include a comprehensive README.md:

```markdown
# Module Name

Brief one-line description.

## Overview

Detailed description of what the module does, when to use it, and key features.

## Features

- Feature 1
- Feature 2
- Feature 3

## Usage

### Basic Example

```hcl
module "example" {
  source = "../path/to/module"

  # Required inputs
  vpc_cidr = "10.0.0.0/16"

  # Optional inputs
  enable_dns_support = true
}
```

### Complete Example

```hcl
# See examples/complete for full example
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0.0 |

## Resources

| Name | Type |
|------|------|
| aws_vpc.main | resource |
| aws_subnet.public | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| vpc_cidr | The CIDR block for the VPC | `string` | n/a | yes |
| enable_dns_support | Enable DNS support | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | The ID of the VPC |
| subnet_ids | List of subnet IDs |

## Examples

- [Complete](./examples/complete) - Full-featured example with all options
- [Basic](./examples/basic) - Minimal configuration example

## Cost Estimation

Estimated monthly cost: $100-200

Cost factors:
- NAT Gateway: $32.40/month per AZ
- VPC Endpoints: $7.20/month per endpoint
- Data transfer: Variable

Use the [AWS Pricing Calculator](https://calculator.aws/) for detailed estimates.

## Architecture

[Include architecture diagram if applicable]

## Security Considerations

- Encryption at rest enabled by default
- Private subnets for sensitive resources
- NACLs and security groups configured

## Performance

- Deployment time: ~15 minutes
- Supports up to 200 resources
- Tested at scale: 100+ subnets

## Troubleshooting

### Issue: VPC creation fails

**Cause:** CIDR block overlaps with existing VPC

**Solution:** Choose a different CIDR block

## Migration Guide

For migrating from version X to Y, see [Migration Guide](./docs/migration.md)

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md)

## License

See [LICENSE](./LICENSE)

## Maintainers

- Platform Engineering Team (@platform-team)
- Primary: platform-team@example.com
- Backup: sre-team@example.com

## Changelog

See [CHANGELOG.md](./CHANGELOG.md)
```

### CHANGELOG.md Format

Use [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New feature X

### Changed
- Modified behavior of Y

## [1.2.0] - 2025-12-01

### Added
- IPv6 support (#123)
- VPC Flow Logs integration (#124)

### Changed
- Improved CIDR calculation logic (#125)
- Updated AWS provider requirement to >= 5.0.0

### Fixed
- Fixed NAT Gateway creation in single AZ mode (#126)

### Security
- Added encryption for flow logs (#127)

## [1.1.0] - 2025-11-01

### Added
- Support for VPC endpoints
- Optional DNS resolution configuration

## [1.0.0] - 2025-10-01

### Added
- Initial stable release
- Full VPC creation with subnets
- NAT Gateway support
- Internet Gateway support
```

---

## Testing Requirements

### Unit Tests

**MUST include unit tests for:**
- Variable validation
- Local calculations
- Conditional logic

**Framework:** Terraform test or Terratest

**Example (Terraform test):**
```hcl
# tests/unit/vpc_cidr_validation.tftest.hcl

run "valid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/16"
  }

  assert {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR validation failed"
  }
}

run "invalid_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "invalid"
  }

  expect_failures = [
    var.vpc_cidr
  ]
}
```

**Example (Terratest):**
```go
// tests/unit/vpc_test.go

package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCCIDRValidation(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../",
        Vars: map[string]interface{}{
            "vpc_cidr": "10.0.0.0/16",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndPlan(t, terraformOptions)

    // Additional assertions
}
```

### Integration Tests

**MUST include integration tests for:**
- Resource creation
- Resource relationships
- Output validation

**Example:**
```go
// tests/integration/vpc_integration_test.go

func TestVPCCreation(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../../examples/complete",
        Vars: map[string]interface{}{
            "vpc_cidr": "10.0.0.0/16",
            "availability_zones": []string{"us-east-1a", "us-east-1b"},
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Validate outputs
    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcID)

    // Validate AWS resources
    aws := terraform.GetAWSVPC(t, vpcID, "us-east-1")
    assert.Equal(t, "10.0.0.0/16", aws.CidrBlock)
}
```

### Test Coverage Requirements

| Maturity Level | Unit Tests | Integration Tests | Coverage |
|----------------|------------|-------------------|----------|
| Experimental | Optional | Optional | N/A |
| Alpha | Required | Optional | > 50% |
| Beta | Required | Required | > 70% |
| Stable | Required | Required | > 80% |
| Mature | Required | Required | > 90% |

---

## Security Requirements

### Security Scanning

**MUST pass all security scans before promotion:**

1. **Checkov** - Infrastructure as Code security scanner
2. **tfsec** - Terraform security scanner
3. **Terrascan** - Infrastructure as Code scanner
4. **AWS Config Rules** - Compliance validation

**Example CI/CD integration:**
```yaml
security:
  stage: test
  script:
    - checkov -d . --framework terraform
    - tfsec .
    - terrascan scan -t terraform -d .
  allow_failure: false
```

### Security Best Practices

**MUST implement:**
- Encryption at rest for all storage
- Encryption in transit for all communication
- Least privilege IAM policies
- No hardcoded credentials
- Secrets in AWS Secrets Manager or SSM Parameter Store
- Network isolation (private subnets)
- Security groups with minimal access
- Logging and monitoring enabled

**Example:**
```hcl
# ✓ Good - encryption enabled
resource "aws_s3_bucket" "example" {
  bucket = "${local.name_prefix}-bucket"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.example.arn
      }
    }
  }
}

# ✗ Bad - no encryption
resource "aws_s3_bucket" "example" {
  bucket = "${local.name_prefix}-bucket"
}

# ✓ Good - using Secrets Manager
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.db_password_secret_arn
}

# ✗ Bad - hardcoded password
resource "aws_db_instance" "example" {
  password = "MyPassword123!"  # Never do this!
}
```

### Sensitive Data Handling

**MUST mark sensitive outputs:**
```hcl
output "database_password" {
  description = "The database password"
  value       = random_password.db_password.result
  sensitive   = true  # Prevents display in logs
}

output "private_key" {
  description = "The SSH private key"
  value       = tls_private_key.example.private_key_pem
  sensitive   = true
}
```

---

## Performance Standards

### Resource Limits

**MUST validate:**
- Maximum resource count per module
- Deployment time thresholds
- State file size limits

| Maturity Level | Max Resources | Max Deploy Time | Max State Size |
|----------------|--------------|-----------------|----------------|
| Experimental | 20 | 30 min | 1 MB |
| Alpha | 50 | 20 min | 5 MB |
| Beta | 100 | 15 min | 10 MB |
| Stable | 200 | 10 min | 20 MB |
| Mature | 500 | 10 min | 50 MB |

### Performance Optimization

**SHOULD implement:**
- Parallel resource creation where possible
- Minimize `depends_on` usage
- Use `for_each` over `count` for dynamic resources
- Avoid unnecessary data source lookups
- Cache computed values in locals

**Example:**
```hcl
# ✓ Good - parallel creation with for_each
resource "aws_subnet" "private" {
  for_each = { for idx, az in local.availability_zones : az => idx }

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[each.value]
  availability_zone = each.key
}

# ✗ Bad - serial creation with count
resource "aws_subnet" "private" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]
}
```

---

## Versioning Strategy

### Semantic Versioning

**MUST use Semantic Versioning (SemVer):**

```
MAJOR.MINOR.PATCH

Example: 1.2.3
  1 = Major version (breaking changes)
  2 = Minor version (new features, backward compatible)
  3 = Patch version (bug fixes, backward compatible)
```

### Version Bumping Rules

**MAJOR version** when you make incompatible changes:
- Remove or rename variables
- Remove or rename outputs
- Change variable types
- Change default behaviors that could break existing deployments
- Remove resources

**MINOR version** when you add functionality in a backward compatible manner:
- Add new variables (with defaults)
- Add new outputs
- Add new optional resources
- Add new features (opt-in)

**PATCH version** when you make backward compatible bug fixes:
- Fix bugs
- Update documentation
- Improve error messages
- Performance improvements (no behavior change)

### Pre-release Versions

**Alpha:** `1.0.0-alpha.1`
**Beta:** `1.0.0-beta.1`
**Release Candidate:** `1.0.0-rc.1`

### Version Constraints

**In modules:**
```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"  # Allow minor updates, prevent major
    }
  }
}
```

---

## Quality Gates

### Promotion Checklist

#### Experimental → Alpha
- [ ] Basic functionality works
- [ ] README.md exists
- [ ] Variable descriptions added
- [ ] Unit tests created
- [ ] terraform validate passes
- [ ] terraform fmt applied

#### Alpha → Beta
- [ ] All features implemented
- [ ] API design finalized
- [ ] Integration tests added
- [ ] At least 2 examples created
- [ ] Documentation complete
- [ ] Security scans passing
- [ ] Performance benchmarks met

#### Beta → Stable
- [ ] In Beta for 30+ days
- [ ] No critical bugs
- [ ] Test coverage > 80%
- [ ] Used in production by 3+ teams
- [ ] Performance benchmarks validated
- [ ] Security review completed
- [ ] Cost estimates validated
- [ ] Migration guide created (if applicable)

#### Stable → Mature
- [ ] In Stable for 180+ days
- [ ] Zero critical bugs in last 90 days
- [ ] Performance optimizations applied
- [ ] Multiple case studies available
- [ ] Active community usage
- [ ] Test coverage > 90%

### Continuous Quality Checks

**Automated checks on every commit:**
```yaml
quality:
  stage: test
  script:
    # Formatting
    - terraform fmt -check -recursive

    # Validation
    - terraform init
    - terraform validate

    # Linting
    - tflint --config=.tflint.hcl

    # Security
    - checkov -d . --framework terraform
    - tfsec .

    # Documentation
    - terraform-docs markdown . --output-file README.md --check

    # Testing
    - go test ./tests/unit/... -v
    - go test ./tests/integration/... -v -timeout 30m
```

---

## Appendix A: Templates

### Module Scaffold

Use the scaffolding tool to generate a new module:

```bash
./bin/alexandria scaffold \
  --name my-module \
  --category foundations/networking \
  --maturity experimental \
  --complexity intermediate
```

This generates all required files with proper structure.

### Code Review Checklist

Use this checklist when reviewing module pull requests:

**Structure:**
- [ ] Follows standard directory layout
- [ ] All required files present
- [ ] .alexandria.yaml properly configured

**Code Quality:**
- [ ] terraform fmt applied
- [ ] Variable descriptions complete
- [ ] Output descriptions complete
- [ ] Proper validation rules
- [ ] No hardcoded values
- [ ] Proper error messages

**Documentation:**
- [ ] README.md complete and accurate
- [ ] CHANGELOG.md updated
- [ ] Examples provided and tested
- [ ] Architecture documented

**Testing:**
- [ ] Unit tests present
- [ ] Integration tests present
- [ ] Tests passing
- [ ] Coverage meets requirements

**Security:**
- [ ] Security scans passing
- [ ] No secrets in code
- [ ] Encryption enabled
- [ ] Least privilege IAM
- [ ] Sensitive outputs marked

**Performance:**
- [ ] Resource count acceptable
- [ ] Deploy time acceptable
- [ ] Optimizations applied

---

## Appendix B: Tools

### Required Tools

- Terraform >= 1.5.0
- terraform-docs >= 0.16.0
- tflint >= 0.47.0
- checkov >= 2.3.0
- tfsec >= 1.28.0
- terrascan >= 1.18.0

### Recommended Tools

- pre-commit - Git hook framework
- infracost - Cost estimation
- terraform-compliance - BDD for Terraform
- terragrunt - DRY Terraform configurations

### Installation

```bash
# macOS
brew install terraform terraform-docs tflint checkov tfsec terrascan

# Linux
# See individual tool documentation
```

---

## Appendix C: FAQ

**Q: What if my module doesn't fit into one category?**
A: Choose the primary category. Use tags to indicate secondary categories.

**Q: How do I version a major breaking change?**
A: Bump MAJOR version, create migration guide, mark old version as deprecated.

**Q: What maturity level should I start with?**
A: Start with "experimental" and promote based on quality gates.

**Q: How long should a module stay in each maturity level?**
A: Minimum: experimental (no min), alpha (1 week), beta (30 days), stable (180 days).

**Q: Can I skip maturity levels?**
A: No. Each level has specific quality requirements that must be met.

**Q: What if my tests take too long?**
A: Split into fast unit tests (always run) and slow integration tests (pre-release only).

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2025-12-02 | Architecture Team | Initial release |

---

**Questions or Feedback:** Contact Platform Engineering Team
