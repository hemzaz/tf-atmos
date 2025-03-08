# Gaia

A Python-based CLI for managing Terraform deployments with Atmos.

> **IMPORTANT**: This project has been renamed from `atmos-cli` to `gaia` to avoid confusion with the primary Atmos tool. The `atmos-cli` command continues to work as an alias but is deprecated. Please use `gaia` in all new scripts.

## Overview

This project provides tools for deploying and managing infrastructure with Terraform and Atmos, including:

- Component discovery and dependency management
- Environment onboarding and configuration
- Drift detection and remediation
- State lock management
- Certificate handling

## Installation

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/example/tf-atmos.git
cd tf-atmos

# Install the package
pip install -e .

# Start Redis (for async operations)
brew install redis  # or apt-get install redis-server
brew services start redis
```

### Requirements

- Python 3.8+
- Terraform
- Atmos CLI

See `requirements.txt` for Python dependencies.

## Usage

### Python CLI (Recommended)

```bash
# Get help
gaia --help

# Apply an environment
gaia workflow apply-environment --tenant acme --account prod --environment use1

# Plan an environment
gaia workflow plan-environment --stack acme-prod-use1

# Use async mode for long-running operations
gaia --async workflow apply-environment --tenant acme --account prod --environment use1
```

### Simplified Operations Script

For common operations, use the simplified `atmos-ops` script:

```bash
# Apply components
atmos-ops apply

# Detect drift
atmos-ops drift 

# Manage state
atmos-ops state list
```

### Legacy Bash Scripts

Bash scripts are maintained for backward compatibility in `scripts/compatibility/`:

```bash
# Apply components
./scripts/compatibility/component-operations.sh apply
```

## Directory Structure

- **gaia/**: Python implementation
- **bin/**: Executable scripts
- **scripts/**: Utility scripts
  - **certificates/**: Certificate management (bash)
  - **compatibility/**: Legacy bash scripts
  - **templates/**: Template files
- **workflows/**: Atmos workflow definitions

## Features

### Asynchronous Tasks

Gaia supports asynchronous task processing with Celery:

```bash
# Start the Celery worker
python scripts/celery-worker.py

# Run commands asynchronously
gaia --async workflow apply-environment -t acme -a prod -e use1

# Manage tasks
gaia task status <task-id>
gaia task list
gaia task revoke <task-id>
```

### Environment Templating

Create and update environment configurations with Copier:

```bash
# Create a new environment
gaia template create-environment -t acme -a prod -e use1 --vpc-cidr 10.0.0.0/16

# Update an existing environment
gaia template update-environment -t acme -a prod -e use1
```

## Maintenance

The codebase is transitioning from bash to Python for better maintainability:

- All new features are implemented in Python
- Bash scripts are maintained for backward compatibility
- Certificate management scripts will be migrated to Python in a future release
- The project has been renamed from `atmos-cli` to `gaia`

## License

MIT