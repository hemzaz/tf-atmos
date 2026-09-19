# Validate Infrastructure

Validate all Terraform configurations and ensure they are properly formatted and error-free.

## What this does
- Runs terraform fmt -check on all .tf files
- Validates Terraform syntax and configuration
- Checks Atmos stack configurations
- Verifies component dependencies

## Commands to run
```bash
# Quick validation
make validate

# Or with Atmos directly
atmos workflow validate -f validate

# Validate specific environment
atmos workflow validate -f validate -s fnx-dev-testenv-01

# Validate with auto-fix formatting
terraform fmt -recursive components/terraform
```

## Expected output
- ✅ All configurations should be valid
- ❌ If errors found, review the specific files mentioned
- 🔧 Use `make lint` or `terraform fmt -recursive components/terraform` to fix formatting issues

## Troubleshooting
If validation fails:
1. Check the error messages for specific issues
2. Run `make doctor` for system diagnostics
3. Ensure AWS credentials are configured: `aws sts get-caller-identity`
4. Verify you're in the project root directory with `atmos.yaml`