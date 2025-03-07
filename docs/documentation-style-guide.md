# Documentation Style Guide

_Last Updated: February 27, 2025_

This style guide establishes standards for documentation in the Atmos project to ensure consistency and clarity across all documentation files.

## Table of Contents

- [Terminology](#terminology)
- [File Organization](#file-organization)
- [Formatting](#formatting)
- [Code Examples](#code-examples)
- [Cross-References](#cross-references)
- [Versioning](#versioning)
- [Date Formats](#date-formats)
- [Templates](#templates)

## Terminology

### Standard Terms

| Term | Usage | Examples |
|------|-------|----------|
| Atmos | Always capitalize "A", lowercase "tmos" | "Atmos framework", "using Atmos" |
| Terraform | Capitalize except when referring to commands | "Terraform component", "run terraform apply" |
| Component names | Singular form, no hyphens | "vpc", "securitygroup", "apigateway" |
| AWS services | Follow AWS capitalization | "API Gateway", "Amazon S3", "AWS Lambda" |
| Account types | Standard terms for account hierarchy | "management", "dev", "staging", "prod", "shared-services" |

### Naming Conventions

1. **Component Names**
   - Use singular form (e.g., "vpc" not "vpcs")
   - Do not use hyphens (e.g., "securitygroup" not "security-group")
   - Use all lowercase (e.g., "apigateway" not "ApiGateway")

2. **Stack Names**
   - Format: `tenant-account-environment` (e.g., "mycompany-dev-us-east-1")
   - Use hyphens as separators, not underscores

3. **Variable Names**
   - Use underscores for multi-word variables (e.g., "vpc_cidr" not "vpc-cidr")
   - Use lowercase for all variable names

4. **File Names**
   - Use kebab-case for documentation files (e.g., "getting-started.md")
   - Use standard Terraform file names for components (main.tf, variables.tf, outputs.tf, provider.tf)

## File Organization

### Standard Directory Structure

```
.
├── GUIDELINES.md              # Code style guidelines
├── atmos.yaml                 # Atmos configuration
├── components/                # Terraform components
│   └── terraform/
│       ├── component/         # Each component in its own directory
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── provider.tf
│       │   ├── README.md
│       │   └── policies/      # Optional for policy templates
├── docs/                      # Documentation
│   ├── diagrams/              # Architecture diagrams
│   └── *.md                   # General guide documents
├── examples/                  # Example implementations
├── integrations/              # CI/CD and external tool integrations
│   ├── jenkins/               # Jenkins integration files
│   ├── atlantis/              # Atlantis integration files
│   └── README.md              # Integration documentation
├── stacks/                    # Stack configurations
├── templates/                 # Reusable templates
└── workflows/                 # Workflow definitions
```

### Component Structure

Each component should have:

```
components/terraform/component/
├── main.tf           # Main resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── provider.tf       # Provider configuration
├── README.md         # Component documentation
└── policies/         # Optional JSON templates
```

## Formatting

### Markdown Standards

1. **Headings**
   - Document title: H1 (single # per document)
   - Main sections: H2 (##)
   - Subsections: H3 (###)
   - Further nesting: H4 (####) and beyond
   - Use Title Case for all headings

2. **Lists**
   - Use hyphens (-) for unordered lists
   - Use consistent indentation (2 spaces) for nested lists
   - Use numbers for ordered lists

3. **Emphasis**
   - Use **bold** for emphasis
   - Use *italic* for introducing new terms
   - Use `code font` for code references

4. **Tables**
   - Include header row
   - Align column content consistently
   - Use title case for column headers

5. **Blockquotes**
   - Use for important notes or quotes
   - Keep formatting minimal within blockquotes

6. **Horizontal Rules**
   - Use sparingly to separate major sections
   - Add blank lines before and after

### Standard Sections

Each document should include:

1. **Title** (H1 heading)
2. **Last Updated Date**
3. **Introduction/Overview**
4. **Table of Contents** (for longer documents)
5. **Main Content Sections**
6. **Related Resources** (when applicable)

## Code Examples

### Code Blocks

Use triple backticks with language specifier:

````markdown
```hcl
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  
  tags = {
    Name = "${var.environment}-vpc"
  }
}
```
````

### Command Examples

For bash/shell commands:

````markdown
```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=us-east-1
```
````

### YAML Examples

For Atmos configuration:

````markdown
```yaml
vars:
  tenant: mycompany
  environment: dev
  region: us-east-1
  
  vpc_cidr: "10.0.0.0/16"
```
````

## Cross-References

### Internal Links

Use relative paths for links to other documents:

```markdown
See the [Workflow Guide](./workflows.md) for more information.
```

### Section Links

Use lowercase with hyphens for section anchors:

```markdown
Refer to the [authentication methods](#authentication-methods) section.
```

### External Links

Use descriptive link text and full URLs:

```markdown
Read the [AWS API Gateway documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html).
```

## Versioning

### Version References

1. **Terraform Version**
   - Always specify as "Terraform (version X.Y.Z or later)"
   - Minimum required version: 1.0.0

2. **Atmos Version**
   - Always specify as "Atmos CLI (version X.Y.Z or later)"
   - Minimum required version: 1.5.0

3. **Provider Versions**
   - AWS Provider: 4.9.0 or later

4. **Other Dependencies**
   - List with specific minimum versions

## Date Formats

### Standard Date Format

- Use "Month DD, YYYY" format (e.g., "February 27, 2025")
- Include in all documents under the title: _Last Updated: February 27, 2025_

### Example Dates

- Use consistent placeholder dates in examples
- Prefer using ISO format for machine-readable dates (YYYY-MM-DD)

## Templates

### Document Template

```markdown
# Document Title

_Last Updated: Month DD, YYYY_

Brief introduction and purpose of the document.

## Table of Contents

- [Section 1](#section-1)
- [Section 2](#section-2)
- [Section 3](#section-3)

## Overview

High-level summary of the document's content and why it's important.

## Section 1

Content for section 1.

### Subsection 1.1

Content for subsection 1.1.

## Section 2

Content for section 2.

## Section 3

Content for section 3.

## Best Practices

Recommended approaches and patterns related to this topic.

## Troubleshooting

Common issues and their solutions related to this topic.

## Related Resources

- [Related Resource 1](./related-resource-1.md) - Brief description
- [Related Resource 2](./related-resource-2.md) - Brief description
- [External Reference](https://external-link.com) - Brief description

## Appendix

Additional reference information, if applicable.
```

### Component README Template

```markdown
# Component Name

_Last Updated: Month DD, YYYY_

Brief description of the component and its purpose.

## Overview

Detailed description of what the component creates and its main features.

## Architecture

[Include architecture diagram if applicable]

Explain the architecture of the component, including the resources it creates and their relationships.

## Features

- Feature 1: Brief description
- Feature 2: Brief description
- Feature 3: Brief description

## Usage

### Basic Usage

```yaml
components:
  terraform:
    component-name:
      vars:
        key: value
        # Basic usage example
```

### Advanced Configuration

```yaml
components:
  terraform:
    component-name:
      vars:
        # Advanced configuration example with comments
        key1: value1  # Description of this setting
        key2: value2  # Description of this setting
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `var1` | Description of var1 | `string` | `null` | Yes |
| `var2` | Description of var2 | `number` | `42` | No |

## Outputs

| Name | Description |
|------|-------------|
| `output1` | Description of output1 |
| `output2` | Description of output2 |

## Examples

See the [examples directory](../../../examples/component-name/) for working examples.

### Example 1: Basic Implementation

```yaml
# Example 1 code
```

### Example 2: Advanced Implementation

```yaml
# Example 2 code
```

## Related Components

- [Component 1](../component1/README.md) - Brief description of relationship
- [Component 2](../component2/README.md) - Brief description of relationship

## Troubleshooting

### Common Issue 1

Description of the issue and its solution.

### Common Issue 2

Description of the issue and its solution.

## Resources

- [AWS Documentation](link-to-aws-docs)
- [Terraform Registry](link-to-terraform-registry)
- [Related Guide](../../docs/related-guide.md)
```

---

By following this style guide, we maintain consistency across all documentation, making it easier for users to understand and utilize the Atmos framework effectively.