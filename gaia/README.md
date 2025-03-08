# Gaia - Python CLI for Terraform Atmos

Gaia is a Python-based CLI for Terraform Atmos that provides enhanced functionality and async task processing.

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

## Celery Worker

For asynchronous task processing:

```bash
# Start Redis (if not already running)
redis-server

# Start Celery worker
python scripts/celery-worker.py

# Optional: Start Flower dashboard
celery -A gaia.cli.celery_app flower --port=5555
```

## Usage

```bash
# Get help
gaia --help

# Run operations asynchronously
gaia --async workflow apply-environment -t acme -a prod -e use1

# Manage tasks
gaia task status <task-id>
gaia task list
gaia task revoke <task-id>

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