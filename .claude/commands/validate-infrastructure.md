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

# Or with Gaia CLI
gaia workflow validate

# Validate specific environment
gaia workflow validate --tenant fnx --account dev --environment testenv-01

# Validate with auto-fix formatting
gaia workflow lint --fix
```

## Expected output
- ✅ All configurations should be valid
- ❌ If errors found, review the specific files mentioned
- 🔧 Use `make lint` or `gaia workflow lint --fix` to fix formatting issues

## Troubleshooting
If validation fails:
1. Check the error messages for specific issues
2. Run `make doctor` for system diagnostics
3. Ensure AWS credentials are configured: `aws sts get-caller-identity`
4. Verify you're in the project root directory with `atmos.yaml`