# Atmos Best Practices Analysis Report

## Executive Summary

This document provides a comprehensive analysis of the tf-atmos project against Atmos best practices, identifying anti-patterns and providing recommendations for improvements.

**Analysis Date:** 2024-12-02
**Project Structure:**
- 19 Terraform components in `/components/terraform/`
- 16+ Atmos workflows in `/workflows/`
- Stack configurations in `/stacks/` with catalog, mixins, and orgs hierarchy

---

## Anti-Patterns Identified

### 1. CRITICAL: Duplicate Import Paths

**Location:** `stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` and `main.yaml`

**Issue:** The same stack is defined twice with different import patterns:
- `testenv-01.yaml` imports from component-specific files in a subdirectory structure
- `main.yaml` imports directly from catalog with `.yaml` extensions

**Impact:** Configuration drift, confusion about which file is authoritative, potential merge conflicts.

**Status:** FIXED - Archived `main.yaml` to `_archived/main.yaml.archived`

### 2. HIGH: Inconsistent Import Extension Usage

**Location:** Multiple stack files

**Issue:** Mixed patterns for import paths:
```yaml
# In main.yaml - uses .yaml extension
import:
  - catalog/network/defaults.yaml
  - catalog/vpc/defaults.yaml

# In testenv-01.yaml - no extension
import:
  - catalog/vpc/defaults
  - catalog/network/defaults
```

**Best Practice:** Always omit the `.yaml` extension in imports for consistency and maintainability.

**Status:** FIXED - Standardized import paths in updated files

### 3. HIGH: Redundant Variable Declarations

**Location:** Multiple catalog and mixin files

**Issue:** Variables like `tenant`, `account`, `environment` are declared at multiple levels redundantly:
```yaml
# catalog/iam/defaults.yaml
vars:
  tenant: "${tenant}"
  account: "${account}"
  environment: "${environment}"
```

These self-referential declarations provide no value.

**Status:** FIXED - Removed redundant vars from catalog files

### 4. MEDIUM: Backend Configuration Duplication

**Location:** All catalog/*/defaults.yaml files

**Issue:** Each catalog component repeats the full backend configuration.

**Best Practice:** Define backend configuration once in `atmos.yaml` and let Atmos auto-generate backend files.

**Status:** DOCUMENTED - Noted in base catalog that backend is centralized in atmos.yaml

### 5. MEDIUM: Variable Mismatch Between Stack and Component

**Location:** `catalog/vpc/defaults.yaml` vs `components/terraform/vpc/variables.tf`

**Issue:** Stack configuration uses `ipv4_primary_cidr_block` but component uses `vpc_cidr`

**Status:** FIXED - Updated to use consistent `vpc_cidr` variable name

### 6. MEDIUM: Missing Component Metadata

**Location:** Several component catalog files

**Issue:** Not all components have complete metadata.

**Status:** PARTIALLY FIXED - Added complete metadata to vpc and iam catalogs

### 7. LOW: Inconsistent Naming Conventions

**Location:** Various files

**Issues:**
- Output typo: `cross_accounr_role_name` (should be `cross_account_role_name`)

**Status:** FIXED - Corrected typo in iam catalog

### 8. LOW: Environment Mixin Structure

**Location:** `stacks/mixins/development.yaml`, `stacks/mixins/production.yaml`

**Issue:** The `terraform:` block should be under `components:` not at root level

**Status:** FIXED - Restructured both development.yaml and production.yaml

### 9. LOW: Duplicate Variable in Component

**Location:** `components/terraform/monitoring/variables.tf`

**Issue:** `eks_cluster_name` was declared twice in the same file

**Status:** FIXED - Removed duplicate variable declaration

---

## Changes Implemented

### New Files Created

| File | Purpose |
|------|---------|
| `/stacks/catalog/_base/defaults.yaml` | Base configuration for all components |
| `/workflows/validate-enhanced.yaml` | Enhanced validation workflow |
| `/docs/ATMOS_PATTERNS.md` | Best practices documentation |
| `/docs/ATMOS_BEST_PRACTICES_ANALYSIS.md` | This analysis report |

### Files Modified

| File | Changes |
|------|---------|
| `/stacks/mixins/development.yaml` | Fixed structure - moved terraform under components |
| `/stacks/mixins/production.yaml` | Fixed structure - moved terraform under components |
| `/stacks/catalog/iam/defaults.yaml` | Removed redundant vars, fixed typo, added imports |
| `/stacks/catalog/vpc/defaults.yaml` | Fixed variable name, added metadata, imports |
| `/stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` | Fixed imports, variable names |
| `/stacks/orgs/fnx/dev/eu-west-2/testenv-01/components/globals.yaml` | Fixed import paths |
| `/stacks/orgs/fnx/dev/eu-west-2/testenv-01/components/networking.yaml` | Fixed variable names |
| `/components/terraform/monitoring/variables.tf` | Removed duplicate variable |

### Files Archived

| File | Reason |
|------|--------|
| `/stacks/orgs/fnx/dev/eu-west-2/testenv-01/main.yaml` | Duplicate stack definition |

---

## Implementation Checklist

- [x] Archive `main.yaml` files, use hierarchical structure
- [x] Remove `.yaml` extensions from imports in key files
- [x] Create `catalog/_base/defaults.yaml` for common settings
- [x] Fix variable name alignment (stack vs component)
- [x] Fix mixin structure (components: terraform:)
- [x] Fix output typos
- [x] Create enhanced validation workflow
- [x] Create documentation for Atmos patterns
- [ ] Enable validation schemas in staging/production
- [ ] Complete metadata for all catalog components
- [ ] Update remaining catalog files with base imports

---

## Validation Commands

```bash
# Run enhanced validation
atmos workflow validate-all -f validate-enhanced.yaml

# Validate specific stack
atmos workflow validate-stack -f validate-enhanced.yaml \
  tenant=fnx account=dev environment=testenv-01

# Lint and format Terraform
atmos workflow lint -f lint.yaml fix=true

# Plan environment
atmos workflow plan -f plan-environment.yaml \
  tenant=fnx account=dev environment=testenv-01
```

---

## Recommendations Summary

### Priority 1 (Critical) - COMPLETED
1. [x] Remove duplicate stack definitions
2. [x] Standardize import path extensions
3. [x] Fix variable name mismatches

### Priority 2 (High) - COMPLETED
1. [x] Remove redundant variable declarations
2. [x] Create base catalog for common settings
3. [x] Fix mixin structure

### Priority 3 (Medium) - IN PROGRESS
1. [ ] Complete component metadata across all catalogs
2. [ ] Enable validation schemas in staging/production
3. [ ] Update all catalog files to import base

### Priority 4 (Low) - PARTIALLY COMPLETED
1. [x] Fix typos in output names
2. [ ] Standardize all naming conventions
3. [ ] Replace hardcoded values with variables in all files

---

## Next Steps

1. Review and test the changes with `atmos workflow validate-all`
2. Update remaining catalog files to import `catalog/_base/defaults`
3. Enable validation schemas in staging and production stacks
4. Complete metadata for all component catalogs
5. Consider implementing a CI pipeline that runs the enhanced validation workflow

---

## Related Documentation

- [ATMOS_PATTERNS.md](/docs/ATMOS_PATTERNS.md) - Best practices and patterns guide
- [atmos.yaml](/atmos.yaml) - Atmos configuration
- [CLAUDE.md](/CLAUDE.md) - Project development guidelines
