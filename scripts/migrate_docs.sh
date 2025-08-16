#!/usr/bin/env bash

# Script to clean up documentation structure:
# - Create a single, clean docs directory structure
# - Preserve atmos-docs subdirectory
# - Remove docs-consolidated

set -e

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/docs-consolidated"
TARGET_DIR="${REPO_ROOT}/docs"
BACKUP_DIR="${REPO_ROOT}/docs.bak.$(date +%Y%m%d_%H%M%S)"

# Log function
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
  log "Error: Source directory $SOURCE_DIR does not exist"
  exit 1
fi

# Step 1: Create backup of current docs directory
log "Creating backup of current docs directory to $BACKUP_DIR"
cp -r "$TARGET_DIR" "$BACKUP_DIR"

# Step 2: Preserve atmos-docs directory
log "Preserving atmos-docs directory"
if [ -d "$TARGET_DIR/atmos-docs" ]; then
  mkdir -p /tmp/atmos-docs-backup
  cp -r "$TARGET_DIR/atmos-docs" /tmp/atmos-docs-backup/
fi

# Step 3: Create clean directory structure
log "Creating clean directory structure"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/core-concepts"
mkdir -p "$TARGET_DIR/environment-management"
mkdir -p "$TARGET_DIR/component-guides"
mkdir -p "$TARGET_DIR/operations"
mkdir -p "$TARGET_DIR/workflows"
mkdir -p "$TARGET_DIR/reference"

# Step 4: Copy consolidated docs to main docs directory
log "Copying documentation to main docs directory"

# Copy core documentation
cp "$SOURCE_DIR/README.md" "$TARGET_DIR/" 2>/dev/null || log "Note: README.md not found in consolidated docs"
cp "$SOURCE_DIR/architecture-guide.md" "$TARGET_DIR/core-concepts/" 2>/dev/null || log "Note: architecture-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/security-best-practices-guide.md" "$TARGET_DIR/core-concepts/" 2>/dev/null || log "Note: security-best-practices-guide.md not found in consolidated docs"

# Copy environment management documentation
cp "$SOURCE_DIR/environment-guide.md" "$TARGET_DIR/environment-management/" 2>/dev/null || log "Note: environment-guide.md not found in consolidated docs"

# Copy component guides
cp "$SOURCE_DIR/eks-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: eks-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/api-gateway-integration-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: api-gateway-integration-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/certificate-management-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: certificate-management-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/iam-role-patterns-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: iam-role-patterns-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/secrets-manager-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: secrets-manager-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/terraform-components-guide.md" "$TARGET_DIR/component-guides/" 2>/dev/null || log "Note: terraform-components-guide.md not found in consolidated docs"

# Copy operations documentation
cp "$SOURCE_DIR/disaster-recovery-guide.md" "$TARGET_DIR/operations/" 2>/dev/null || log "Note: disaster-recovery-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/troubleshooting-guide.md" "$TARGET_DIR/operations/" 2>/dev/null || log "Note: troubleshooting-guide.md not found in consolidated docs"

# Copy workflow documentation
cp "$SOURCE_DIR/cicd-integration-guide.md" "$TARGET_DIR/workflows/" 2>/dev/null || log "Note: cicd-integration-guide.md not found in consolidated docs"
cp "$SOURCE_DIR/terraform-development-guide.md" "$TARGET_DIR/workflows/" 2>/dev/null || log "Note: terraform-development-guide.md not found in consolidated docs"

# Copy any remaining files in the root of docs-consolidated
for file in "$SOURCE_DIR"/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    # Skip files we've already copied
    if [[ "$filename" != "README.md" && 
          "$filename" != "architecture-guide.md" && 
          "$filename" != "security-best-practices-guide.md" && 
          "$filename" != "environment-guide.md" &&
          "$filename" != "eks-guide.md" &&
          "$filename" != "api-gateway-integration-guide.md" &&
          "$filename" != "certificate-management-guide.md" &&
          "$filename" != "iam-role-patterns-guide.md" &&
          "$filename" != "secrets-manager-guide.md" &&
          "$filename" != "disaster-recovery-guide.md" &&
          "$filename" != "troubleshooting-guide.md" &&
          "$filename" != "cicd-integration-guide.md" &&
          "$filename" != "terraform-development-guide.md" &&
          "$filename" != "terraform-components-guide.md" ]]; then
      cp "$file" "$TARGET_DIR/" 2>/dev/null || log "Note: Failed to copy $filename"
      log "Copied additional file: $filename to root directory"
    fi
  fi
done

# Step 5: Restore atmos-docs directory
log "Restoring atmos-docs directory"
if [ -d "/tmp/atmos-docs-backup/atmos-docs" ]; then
  cp -r "/tmp/atmos-docs-backup/atmos-docs" "$TARGET_DIR/"
  rm -rf /tmp/atmos-docs-backup
fi

# Step 6: Update README.md with new structure
log "Updating main README.md with new structure"

cat > "$TARGET_DIR/README.md" << 'EOF'
# AWS Infrastructure Documentation

This directory contains comprehensive documentation for the AWS infrastructure managed with Terraform and Atmos.

## Documentation Structure

### Core Concepts
- [Architecture Guide](core-concepts/architecture-guide.md)
- [Security Best Practices](core-concepts/security-best-practices-guide.md)

### Environment Management
- [Environment Guide](environment-management/environment-guide.md) - Comprehensive guide covering environment creation, templating, and management

### Component Guides
- [EKS Guide](component-guides/eks-guide.md) - Complete guide for EKS clusters, addons, and Istio
- [API Gateway Integration](component-guides/api-gateway-integration-guide.md)
- [Certificate Management](component-guides/certificate-management-guide.md)
- [IAM Role Patterns](component-guides/iam-role-patterns-guide.md)
- [Secrets Manager](component-guides/secrets-manager-guide.md)
- [Terraform Components](component-guides/terraform-components-guide.md) - Component catalog and creation guide

### Operations
- [Disaster Recovery](operations/disaster-recovery-guide.md)
- [Troubleshooting](operations/troubleshooting-guide.md)

### Workflows
- [CI/CD Integration](workflows/cicd-integration-guide.md)
- [Terraform Development](workflows/terraform-development-guide.md)

## Atmos Documentation

For Atmos-specific documentation, see the [atmos-docs](atmos-docs) directory.

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
EOF

# Step 7: Consider removing the docs-consolidated directory
log "Documentation migration complete!"
log "Original docs are backed up to $BACKUP_DIR"
log "To verify the migration, please check the structure and organization of $TARGET_DIR"
log ""
log "The docs-consolidated directory is no longer needed and can be removed with:"
log "  rm -rf \"$SOURCE_DIR\""

# Make the script executable
chmod +x "$0"