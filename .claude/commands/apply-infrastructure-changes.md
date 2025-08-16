# Apply Infrastructure Changes

Apply the planned infrastructure changes to your AWS environment. This will make actual changes to your infrastructure.

## ⚠️ Important Safety Notes
- **ALWAYS run `make plan` first** to review what will change
- This makes **REAL CHANGES** to your AWS infrastructure
- You will be prompted for confirmation before applying
- Have backups and rollback plans ready for production changes

## What this does
- Applies the changes shown in the previous plan
- Creates, modifies, or destroys AWS resources
- Updates Terraform state to match the actual infrastructure
- Provides confirmation prompts for safety

## Commands to run

### Apply with confirmation prompt
```bash
make apply
```

### Apply to specific environment
```bash
# Using make
make apply TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

# Using Gaia CLI (with confirmation)
gaia workflow apply-environment --tenant fnx --account dev --environment testenv-01

# Using Gaia CLI (skip confirmation - BE CAREFUL!)
gaia workflow apply-environment --tenant fnx --account dev --environment testenv-01 --auto-approve
```

### Apply specific component only
```bash
make apply-component COMPONENT=vpc
make apply-component COMPONENT=eks
```

## Pre-flight checklist
Before applying:
1. ✅ Run `make plan` and review all changes
2. ✅ Ensure you have proper AWS credentials: `aws sts get-caller-identity`
3. ✅ Verify you're targeting the correct environment
4. ✅ Check if changes affect production workloads
5. ✅ Have rollback plan ready if needed

## Expected process
1. Shows a summary of planned changes
2. Prompts: "Are you sure you want to continue? (y/N)"
3. If confirmed, applies changes one by one
4. Shows progress and any errors
5. Displays final summary of applied changes

## If something goes wrong
- **Don't panic** - Terraform state helps track what was applied
- Check error messages carefully
- Run `make doctor` for diagnostics
- Consider `make plan` to see current state vs desired state
- For emergencies, you may need to manually fix resources in AWS console

## Post-apply verification
After successful apply:
- Run `make status` to verify infrastructure state
- Check AWS console to confirm resources are healthy
- Test any applications that depend on the changed infrastructure
- Update documentation if major changes were made