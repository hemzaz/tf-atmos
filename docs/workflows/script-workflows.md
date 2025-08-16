# Workflow Scripts

> **IMPORTANT:** The CLI tool has been renamed from `atmos-cli` to `gaia`!
> 
> The old `atmos-cli` command will continue to work as a compatibility alias but is deprecated.
> Please use `gaia` in all new scripts and documentation.

The bash workflow scripts have been replaced by the Python-based implementation in `gaia/`.

For backward compatibility, the original scripts are available in the `../compatibility/` directory.

Please use the new Python implementation for all new development:

```bash
# Instead of bash scripts:
./scripts/workflows/component-operations.sh apply

# Use the Python CLI:
gaia workflow apply-environment --tenant acme --account prod --environment use1
```

## Templating Support

The Python implementation now provides integrated support for Copier-based templating:

### Environment Templating

Create and manage environment configurations:

```bash
# Create a new environment from template
gaia template create-environment --tenant acme --account prod --environment use1 --vpc-cidr 10.0.0.0/16

# Update an existing environment from template changes
gaia template update-environment --tenant acme --account prod --environment use1

# Or use Atmos workflows
atmos workflow template-environment create-environment tenant=acme account=prod environment=use1 vpc-cidr=10.0.0.0/16
```

### Component Templating

Create Terraform components from templates:

```bash
# Create a new component
gaia template create-component --name vpc --description "VPC infrastructure component"

# Create a component from a specific template
gaia template create-component --name eks --template eks-cluster --description "EKS cluster component"

# Or use Atmos workflows
atmos workflow template-component create-component name=vpc description="VPC infrastructure component"
```

### Listing Available Templates

```bash
# List all available templates
gaia template list

# Or use Atmos workflows
atmos workflow template-component list-templates
```

See the templates directory for more information on template customization and additional options.

## Asynchronous Task Processing

Gaia now supports asynchronous operations using Celery for long-running tasks:

```bash
# Run operations asynchronously
gaia --async workflow apply-environment --tenant acme --account prod --environment use1

# Check task status
gaia task status <task-id>

# List tasks (requires Flower)
gaia task list

# Revoke a running task
gaia task revoke <task-id>
```

### Starting Celery Worker

To process asynchronous tasks, you need to start the Celery worker:

```bash
# Start the worker
python scripts/celery-worker.py

# Start the Flower dashboard (optional)
celery -A gaia.cli.celery_app flower --port=5555
```

Redis is required for task queue management. Make sure Redis is installed and running.

### Configuration

You can configure Celery settings in your `.env` file:

```
# Enable async mode by default
ASYNC_MODE=true

# Redis connection
REDIS_URL=redis://localhost:6379/0 

# Number of Celery worker processes
CELERY_WORKERS=4
```
