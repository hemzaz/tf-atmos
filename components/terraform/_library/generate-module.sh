#!/bin/bash
#
# Module Generator for Alexandria Library
# Usage: ./generate-module.sh <category> <module-name> <description>
#

set -e

CATEGORY=$1
MODULE_NAME=$2
DESCRIPTION=$3

if [ -z "$CATEGORY" ] || [ -z "$MODULE_NAME" ] || [ -z "$DESCRIPTION" ]; then
    echo "Usage: $0 <category> <module-name> <description>"
    echo "Example: $0 data-layer s3-bucket 'S3 bucket with all features'"
    exit 1
fi

MODULE_DIR="./${CATEGORY}/${MODULE_NAME}"

echo "Creating module: ${MODULE_NAME} in category: ${CATEGORY}"
echo "Description: ${DESCRIPTION}"

# Create directory structure
mkdir -p "${MODULE_DIR}"/{examples/complete,examples/simple,tests}

# Create versions.tf
cat > "${MODULE_DIR}/versions.tf" << 'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
EOF

# Create variables.tf template
cat > "${MODULE_DIR}/variables.tf" << 'EOF'
variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
EOF

# Create main.tf template
cat > "${MODULE_DIR}/main.tf" << 'EOF'
locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# TODO: Add resource definitions
EOF

# Create outputs.tf template
cat > "${MODULE_DIR}/outputs.tf" << 'EOF'
# TODO: Add output definitions
EOF

# Create CHANGELOG.md
cat > "${MODULE_DIR}/CHANGELOG.md" << EOF
# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - $(date +%Y-%m-%d)

### Added
- Initial release of ${MODULE_NAME} module
- ${DESCRIPTION}
EOF

echo "✅ Module skeleton created at: ${MODULE_DIR}"
echo ""
echo "Next steps:"
echo "1. Edit ${MODULE_DIR}/main.tf - Add resource definitions"
echo "2. Edit ${MODULE_DIR}/variables.tf - Add module-specific variables"
echo "3. Edit ${MODULE_DIR}/outputs.tf - Add outputs"
echo "4. Create ${MODULE_DIR}/README.md - Add documentation"
echo "5. Create examples in ${MODULE_DIR}/examples/"
echo "6. Add tests in ${MODULE_DIR}/tests/"
