# Atmos Workflows

This directory contains Atmos workflow definitions.

## Structure

Workflows follow a clean, modular structure:
- **YAML files** in this directory define the workflow parameters and interface
- **Implementation scripts** in `scripts/workflows/` directory contain the actual logic
- **Utility libraries** extract common functionality for reuse across workflows

## Available Workflows

### Environment Management

- `create-environment-template.yaml` - Creates a new environment using Copier templates
- `update-environment-template.yaml` - Updates an existing environment with latest template changes
- `onboard-environment.yaml` - Onboards a complete new environment with infrastructure

### Deployment & Operations

- `plan-environment.yaml` - Plans changes to an environment with dynamic component discovery
- `apply-environment.yaml` - Applies changes to an environment with dependency-based ordering
- `destroy-environment.yaml` - Destroys an environment in reverse dependency order
- `drift-detection.yaml` - Detects infrastructure drift in a dependency-aware manner

### Quality Assurance

- `lint.yaml` - Runs comprehensive linting with multiple tools and generates documentation 
- `validate.yaml` - Validates Terraform configurations with dynamic component discovery

## Usage

Workflows are executed using the `atmos workflow` command:

```bash
# Environment Management
atmos workflow create-environment-template tenant=mycompany account=dev environment=test-01 vpc_cidr=10.0.0.0/16
atmos workflow update-environment-template tenant=mycompany account=dev environment=test-01
atmos workflow onboard-environment tenant=mycompany account=dev environment=test-01 vpc_cidr=10.0.0.0/16

# Infrastructure Operations
atmos workflow plan-environment tenant=mycompany account=dev environment=test-01
atmos workflow apply-environment tenant=mycompany account=dev environment=test-01 auto_approve=true
atmos workflow destroy-environment tenant=mycompany account=dev environment=test-01 confirm=true
atmos workflow drift-detection tenant=mycompany account=dev environment=test-01

# Quality Assurance
atmos workflow lint fix=true
atmos workflow validate tenant=mycompany account=dev environment=test-01
```

## Core Components

The workflow system uses several reusable scripts:

1. **component-discovery.sh** - Automatically discovers components in an environment, analyzes their dependencies, and sorts them in the correct order
2. **component-operations.sh** - Provides operations (apply, plan, validate, destroy, drift) on components
3. **lint-operations.sh** - Centralizes linting operations with multiple tools
4. **install-tools.sh** - Handles dynamic installation of required tools

## Design Principles

1. **Separation of Concerns** - YAML files define the interface, shell scripts contain the implementation
2. **DRY (Don't Repeat Yourself)** - Common logic is extracted into utility functions
3. **Self-Documentation** - Clear parameter names and descriptions
4. **Consistency** - Common parameter names and formats across workflows
5. **Progressive Enhancement** - Basic operations work in non-interactive mode, with additional features in interactive mode
6. **Dynamic Discovery** - Components and their dependencies are automatically discovered and ordered
7. **Tool Independence** - Workflows adapt to available tools, installing dependencies as needed
8. **Error Handling** - Robust error handling with clear messaging and proper exit codes