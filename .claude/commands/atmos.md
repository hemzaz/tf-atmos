# Atmos Commands

Quick reference for Atmos commands in this project.

## Validation & Linting
```bash
atmos workflow lint                    # Lint all configurations
atmos workflow validate               # Validate all components
atmos terraform validate <component> -s <stack>  # Validate specific component
```

## Planning & Deployment  
```bash
atmos workflow plan-environment tenant=<tenant> account=<account> environment=<environment>
atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>
atmos terraform plan <component> -s <stack>
```

## Stack Management
```bash
atmos describe stacks                 # List all stacks
atmos describe component <component> -s <stack>  # Show component config
atmos list components                 # List all components
```

## Common Stacks
- `fnx-dev-testenv-01` - Main development environment

## Workflow Operations
```bash
atmos workflow drift-detection        # Check for configuration drift
atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<cidr>
atmos workflow import                 # Import existing resources
```