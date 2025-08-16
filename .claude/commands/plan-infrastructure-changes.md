# Plan Infrastructure Changes

Safely preview what changes will be made to your infrastructure without actually applying them.

## What this does
- Shows what resources will be created, modified, or destroyed
- Validates the configuration before making changes
- Provides a safe way to review changes before applying
- Works with the default stack (fnx-testenv-01-dev)

## Commands to run

### Quick plan with defaults
```bash
make plan
```

### Plan specific environment
```bash
# Using make
make plan TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

# Using Gaia CLI
gaia workflow plan-environment --tenant fnx --account dev --environment testenv-01
```

### Plan specific component
```bash
# Plan just VPC changes
make plan-component COMPONENT=vpc

# Plan just EKS changes  
make plan-component COMPONENT=eks
```

### Plan with custom parameters
```bash
make plan TENANT=fnx ACCOUNT=staging ENVIRONMENT=staging-01
```

## Expected output
- `Plan: X to add, Y to change, Z to destroy`
- Review the planned changes carefully
- Green = additions, Yellow = modifications, Red = deletions

## Safety notes
- Planning is always safe - it never makes actual changes
- Always plan before applying changes
- Review the output carefully, especially any destroy operations
- If you see unexpected destroys, investigate before applying

## Next steps
After reviewing the plan:
- If changes look good: `make apply`
- If you need to modify something: make your changes and plan again
- If you see issues: `make doctor` for diagnostics