# Gaia - Python CLI for Terraform Atmos

Gaia is a secure, performant Python-based CLI for managing Terraform deployments with the Atmos toolchain. It powers all Atmos workflows.

## Overview

Gaia provides enterprise-grade tools for deploying and managing infrastructure with Terraform and Atmos, including:

- High-performance component discovery with intelligent caching
- Dependency resolution and management with cycle detection
- Environment onboarding and configuration with templates
- Advanced drift detection and remediation
- State lock management with safety mechanisms
- Secure certificate handling and rotation
- Thread-safe operations for concurrent tasks

## Features

- **Asynchronous Task Processing**: Use Celery for long-running operations
- **Environment Templating**: Create and update environment configurations with Copier
- **Component Templating**: Generate Terraform components from templates 
- **Workflow Operations**: Plan, apply, validate, and destroy environments
- **Drift Detection**: Identify infrastructure drift
- **Advanced Dependency Handling**: Automatically determine component execution order
- **Certificate Management**: Secure rotation of AWS ACM certificates with Kubernetes integration

## Installation

```bash
# Install dependencies
pip install -r requirements.txt

# Install the package
pip install -e .

# Optional: Start Redis for async operations (recommended for production)
# Redis connection is automatically validated - falls back to local execution if unavailable
brew install redis  # or apt-get install redis-server
brew services start redis
```

## Configuration

Gaia can be configured using environment variables or config files:

```bash
# Basic configuration
export ASYNC_MODE=true  # Enable async tasks by default
export REDIS_URL=redis://localhost:6379/0

# Component paths
export COMPONENTS_DIR=components/terraform
export STACKS_BASE_DIR=stacks
```

Gaia can also be configured through these configuration files:
- `.atmos.env` in project root
- `.env` in project root
- `~/.atmos/config`

Key configuration options:
- `REDIS_URL`: URL for Redis (defaults to localhost)
- `CELERY_WORKERS`: Number of concurrent workers (defaults to 4)
- `ASYNC_MODE`: Enable async mode by default (true/false)

## Asynchronous Tasks

Gaia supports robust asynchronous task processing with Celery:

```bash
# Start the Celery worker
python scripts/celery-worker.py

# Run commands asynchronously
gaia --async workflow apply-environment -t acme -a prod -e use1

# List and manage tasks directly from CLI
gaia task list --days 3 --status SUCCESS
gaia task status <task-id>
gaia task revoke <task-id> --terminate

# Optional: Start Flower dashboard for monitoring
celery -A gaia.cli.celery_app flower --port=5555
```

## Usage

```bash
# Get help
gaia --help

# Apply an environment
gaia workflow apply-environment --tenant acme --account prod --environment use1

# Plan an environment with drift detection
gaia workflow plan-environment --tenant acme --account prod --environment use1 --detect-drift

# Validate components
gaia workflow validate --tenant acme --account prod --environment use1

# Use async mode for long-running operations
gaia --async workflow apply-environment -t acme -a prod -e use1

# Manage tasks
gaia task status <task-id>
gaia task list
gaia task revoke <task-id>

# Environment Templating
gaia template create-environment -t acme -a prod -e use1 --vpc-cidr 10.0.0.0/16 --validate
gaia template update-environment -t acme -a prod -e use1

# Certificate Management
gaia certificate rotate --secret example-com-cert --namespace istio-system --acm-arn arn:aws:acm:us-west-2:123456789012:certificate/xxxxx
```

### Certificate Rotation

The certificate management module provides secure certificate rotation for AWS ACM certificates, synchronizing them with Kubernetes using External Secrets Operator:

```bash
# Rotate a certificate with a new ACM certificate
gaia certificate rotate \
  --secret example-com-cert \
  --namespace istio-system \
  --acm-arn arn:aws:acm:us-west-2:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --region us-west-2 \
  --restart-pods

# Use a workflow for certificate rotation
gaia workflow rotate-certificate \
  secret_name=example-com-cert \
  namespace=istio-system \
  acm_arn=arn:aws:acm:us-west-2:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  restart_pods=true
```

Key improvements over shell implementation:
- Enhanced security with proper handling of sensitive certificate data
- Robust error handling and recovery
- Cross-platform compatibility
- AWS SDK integration with proper retry handling

For more details on usage, see the project documentation.

## High-Performance Component Operations

Gaia includes optimized performance for operations on large codebases:

- Efficient component discovery with class-level caching
- Thread-safe operations with proper locking
- Memory limits to prevent resource exhaustion
- Consolidated dependency handling in Terraform

## Secure Operations

Enhanced security features have been implemented across the codebase:

- Secure temporary file handling with proper permissions
- Script verification with checksum validation
- Command injection prevention
- Proper credential and key management
- Enhanced logging and error handling

## Directory Structure

- **discovery.py**: Component discovery with caching
- **operations.py**: Core operations with memory protections
- **certificates.py**: Secure certificate management
- **utils.py**: Utility functions with security enhancements
- **cli.py**: Command line interface
- **config.py**: Configuration management
- **tasks.py**: Asynchronous task handling
- **templating.py**: Template processing logic