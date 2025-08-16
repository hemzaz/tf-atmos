# Gaia - Simplified Python CLI for Atmos Operations

Gaia 2.0 is a lightweight, fast Python CLI wrapper around native Atmos commands. It provides a simplified interface for common Atmos workflows without unnecessary complexity.

## Overview

Gaia 2.0 focuses on simplicity and reliability:

- **Direct Atmos Integration**: Thin wrapper around native `atmos` commands
- **Minimal Dependencies**: Only requires Typer for CLI interface
- **Fast Startup**: No complex initialization or async overhead
- **Reliable**: Direct subprocess calls to proven Atmos toolchain
- **Maintainable**: Simple, readable codebase (~150 lines vs 700+ in v1)

## Architecture

Gaia 2.0 uses a nuclear simplification approach:
- **No async/Celery complexity**: Direct synchronous calls to Atmos
- **No redundant wrappers**: Commands map directly to `atmos` CLI
- **No over-engineering**: Simple subprocess execution with proper error handling

## Installation

```bash
# Install dependencies (minimal!)
pip install -r requirements.txt

# Install the package
pip install -e .
```

## Usage

### Workflow Operations
```bash
# Validate all components
gaia workflow validate

# Lint code
gaia workflow lint

# Plan environment changes
gaia workflow plan-environment --tenant fnx --account dev --environment testenv-01

# Apply environment changes  
gaia workflow apply-environment --tenant fnx --account dev --environment testenv-01
```

### Direct Terraform Operations
```bash
# Plan a specific component
gaia terraform plan vpc --stack fnx-dev-testenv-01

# Apply a component
gaia terraform apply eks --stack fnx-dev-testenv-01

# Validate a component
gaia terraform validate rds --stack fnx-dev-testenv-01
```

### Stack Management
```bash
# List all stacks
gaia list stacks

# Describe a specific stack
gaia describe stack --stack fnx-dev-testenv-01

# List components in a stack
gaia list components --stack fnx-dev-testenv-01
```

## Key Features

- **Simple Command Structure**: All commands map directly to native `atmos` operations
- **Proper Error Handling**: Clear error messages and appropriate exit codes
- **Fast Execution**: No startup overhead from complex frameworks
- **Transparent Operations**: Shows exactly which `atmos` commands are being executed
- **Clean Architecture**: Single-file CLI with clear, maintainable code

## Migration from Gaia 1.x

Gaia 2.0 removes the complex async/Celery infrastructure in favor of direct command execution:

- ✅ **Removed**: Celery workers, Redis backend, async task management
- ✅ **Removed**: Complex operation classes with unnecessary abstractions
- ✅ **Removed**: Circular imports and broken module dependencies
- ✅ **Added**: Direct subprocess calls to `atmos` commands
- ✅ **Added**: Simplified error handling and user feedback
- ✅ **Added**: Fast startup and execution

## Development

The codebase is intentionally simple:

- **cli.py**: Main CLI interface (~150 lines)
- **requirements.txt**: Minimal dependencies (just typer)
- **setup.py**: Standard Python package setup
- **README.md**: This documentation

No complex module structure, no async frameworks, no over-engineering.