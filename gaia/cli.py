#!/usr/bin/env python3
"""
Main CLI module for Gaia operations
"""

import os
import sys
import typer
import logging
from typing import List, Optional
import celery
from celery import Celery

from .config import AtmosConfig
from .operations import (
    ComponentOperation,
    PlanOperation,
    ApplyOperation,
    ValidateOperation,
    DestroyOperation,
    DriftDetectionOperation,
    lint_code,
    import_resource,
    validate_components
)
from .certificates import rotate_certificate
from .templating import EnvironmentTemplate
from .templates import ComponentTemplate
from .discovery import ComponentDiscovery
from .logger import setup_logger

# Setup application
app = typer.Typer(help="Gaia - Python implementation for Terraform Atmos operations")
config = AtmosConfig()
logger = setup_logger()

# Setup Celery
# Use configuration from AtmosConfig for Redis connection
config = get_config()
redis_url = config.redis_url

# Try to validate Redis connection before configuring Celery
def validate_redis_connection(url):
    """Validate Redis connection and return True if successful, False otherwise."""
    try:
        import redis
        client = redis.from_url(url, socket_timeout=2.0)
        client.ping()
        return True
    except Exception as e:
        logger.warning(f"Redis connection failed: {e}. Async tasks will not be available.")
        return False

# Create Celery app with configurable broker/backend
redis_available = validate_redis_connection(redis_url)
if redis_available:
    celery_app = Celery('gaia',
                       broker=redis_url,
                       backend=redis_url)
                       
    celery_app.conf.update(
        task_serializer='json',
        accept_content=['json'],
        result_serializer='json',
        timezone='UTC',
        enable_utc=True,
        worker_concurrency=config.celery_workers,
        broker_connection_retry=True,
        broker_connection_retry_on_startup=True,
        broker_connection_max_retries=5,
        task_acks_late=True,
        task_reject_on_worker_lost=True,
    )
else:
    # Create a dummy Celery app that will raise proper errors when used
    celery_app = Celery('gaia')
    celery_app.conf.update(
        task_always_eager=True,  # Tasks will be executed immediately in the same process
        task_eager_propagates=True,  # Errors in tasks will be propagated
    )

# Setup sub-commands
workflow_app = typer.Typer(help="Workflow operations for components and environments")
template_app = typer.Typer(help="Template operations for environments and components")
task_app = typer.Typer(help="Task management for async operations")
certificate_app = typer.Typer(help="Certificate management operations")

# Register sub-commands
app.add_typer(workflow_app, name="workflow")
app.add_typer(template_app, name="template")
app.add_typer(task_app, name="task")
app.add_typer(certificate_app, name="certificate")


@app.callback()
def main(
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Enable verbose output"),
    debug: bool = typer.Option(False, "--debug", "-d", help="Enable debug logging"),
    async_mode: bool = typer.Option(False, "--async", help="Run operations asynchronously with Celery"),
):
    """
    Gaia - Python implementation for Terraform Atmos operations
    """
    # Set logging level based on flags
    if debug:
        logging.getLogger().setLevel(logging.DEBUG)
    elif verbose:
        logging.getLogger().setLevel(logging.INFO)
    else:
        logging.getLogger().setLevel(logging.WARNING)
    
    # Store async mode preference in config
    config.async_mode = async_mode


# Workflow Commands
@workflow_app.command("plan-environment")
def plan_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to plan"),
    parallel: int = typer.Option(4, "--parallel", "-p", help="Number of parallel operations"),
    async_mode: Optional[bool] = typer.Option(None, "--async/--sync", help="Override global async mode setting"),
):
    """
    Plan changes for all components in an environment
    """
    # Use the command-specific async setting if provided, otherwise use global setting
    use_async = async_mode if async_mode is not None else config.async_mode
    
    if use_async:
        # Import here to avoid circular imports
        from .tasks import plan_environment_task
        task = plan_environment_task.delay(
            tenant=tenant,
            account=account,
            environment=environment,
            components=components,
            parallel_count=parallel
        )
        typer.echo(f"Task started with ID: {task.id}")
        typer.echo(f"Run 'gaia task status {task.id}' to check progress")
        return
    
    # Synchronous execution
    operation = PlanOperation(config)
    result = operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel
    )
    if not result:
        sys.exit(1)


@workflow_app.command("apply-environment")
def apply_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to apply"),
    parallel: int = typer.Option(4, "--parallel", "-p", help="Number of parallel operations"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Auto approve terraform apply"),
):
    """
    Apply changes for all components in an environment
    """
    operation = ApplyOperation(config)
    result = operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel,
        auto_approve=auto_approve
    )
    if not result:
        sys.exit(1)


@workflow_app.command("validate")
def validate(
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to validate"),
    parallel: int = typer.Option(8, "--parallel", "-p", help="Number of parallel validations"),
):
    """
    Validate all components in the repository
    """
    operation = ValidateOperation(config)
    result = operation.execute_all(
        components=components,
        parallel_count=parallel
    )
    if not result:
        sys.exit(1)


@workflow_app.command("destroy-environment")
def destroy_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to destroy"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Auto approve terraform destroy"),
):
    """
    Destroy all components in an environment
    """
    operation = DestroyOperation(config)
    result = operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        auto_approve=auto_approve
    )
    if not result:
        sys.exit(1)


@workflow_app.command("drift-detection")
def drift_detection(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to check"),
    parallel: int = typer.Option(4, "--parallel", "-p", help="Number of parallel operations"),
):
    """
    Detect drift for all components in an environment
    """
    operation = DriftDetectionOperation(config)
    result = operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel
    )
    if not result:
        sys.exit(1)


@workflow_app.command("onboard-environment")
def onboard_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    vpc_cidr: str = typer.Option(..., "--vpc-cidr", help="VPC CIDR block"),
    aws_region: str = typer.Option(None, "--region", "-r", help="AWS region"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Auto approve terraform apply"),
):
    """
    Onboard a new environment (create from template and apply)
    """
    # First create the environment from template
    template = EnvironmentTemplate(config)
    template_result = template.create_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        vpc_cidr=vpc_cidr,
        aws_region=aws_region
    )
    
    if not template_result:
        typer.echo("Failed to create environment from template")
        sys.exit(1)
    
    # Then apply the environment
    operation = ApplyOperation(config)
    apply_result = operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        auto_approve=auto_approve
    )
    
    if not apply_result:
        typer.echo("Failed to apply environment")
        sys.exit(1)
    
    typer.echo(f"Environment {tenant}-{account}-{environment} onboarded successfully")


# Template Commands
@template_app.command("list")
def list_templates():
    """
    List available templates
    """
    env_template = EnvironmentTemplate(config)
    comp_template = ComponentTemplate(config)
    
    # Get environment templates
    env_templates = env_template.get_available_templates()
    
    # Get component templates
    component_templates = comp_template.list_component_templates()
    
    if not env_templates and not component_templates:
        typer.echo("No templates found")
        return
    
    if env_templates:
        typer.echo("Environment Templates:")
        for t in env_templates:
            typer.echo(f"  - {t}")
    
    if component_templates:
        typer.echo("\nComponent Templates:")
        for t in component_templates:
            typer.echo(f"  - {t['name']}: {t['description']}")


@template_app.command("create-environment")
def create_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    env_type: str = typer.Option(None, "--env-type", help="Environment type (development, staging, production)"),
    aws_region: str = typer.Option(None, "--region", "-r", help="AWS region"),
    vpc_cidr: str = typer.Option(None, "--vpc-cidr", help="VPC CIDR block"),
    team_email: str = typer.Option(None, "--team-email", help="Team email for notifications"),
    target_dir: str = typer.Option(None, "--target-dir", help="Target directory for environment"),
    eks_cluster: bool = typer.Option(True, "--eks-cluster/--no-eks-cluster", help="Enable EKS cluster"),
    rds_instances: bool = typer.Option(False, "--rds-instances/--no-rds-instances", help="Enable RDS instances"),
    enable_logging: bool = typer.Option(True, "--logging/--no-logging", help="Enable centralized logging"),
    enable_monitoring: bool = typer.Option(True, "--monitoring/--no-monitoring", help="Enable monitoring"),
):
    """
    Create a new environment from template
    """
    template = EnvironmentTemplate(config)
    result = template.create_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        env_type=env_type,
        aws_region=aws_region,
        vpc_cidr=vpc_cidr,
        team_email=team_email,
        target_dir=target_dir,
        eks_cluster=eks_cluster,
        rds_instances=rds_instances,
        enable_logging=enable_logging,
        enable_monitoring=enable_monitoring
    )
    
    if not result:
        typer.echo("Failed to create environment from template")
        sys.exit(1)
    
    typer.echo(f"Environment {tenant}-{account}-{environment} created successfully")


@template_app.command("update-environment")
def update_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    target_dir: str = typer.Option(None, "--target-dir", help="Target directory for environment"),
    overwrite: bool = typer.Option(False, "--overwrite", help="Overwrite all files"),
):
    """
    Update an existing environment from template changes
    """
    template = EnvironmentTemplate(config)
    result = template.update_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        target_dir=target_dir,
        overwrite=overwrite
    )
    
    if not result:
        typer.echo("Failed to update environment from template")
        sys.exit(1)
    
    typer.echo(f"Environment {tenant}-{account}-{environment} updated successfully")


@template_app.command("create-component")
def create_component(
    name: str = typer.Option(..., "--name", "-n", help="Component name"),
    template: str = typer.Option("terraform-component", "--template", "-t", 
                                help="Template to use for the component"),
    description: str = typer.Option(None, "--description", "-d", 
                                  help="Component description"),
    destination: str = typer.Option(None, "--destination", "--dest", 
                                  help="Destination directory (defaults to components/<name>)"),
):
    """
    Create a new component from template
    """
    comp_template = ComponentTemplate(config)
    
    result = comp_template.create_component(
        component_name=name,
        template=template,
        description=description,
        destination=destination
    )
    
    if not result:
        typer.echo(f"Failed to create component {name}")
        sys.exit(1)
    
    typer.echo(f"Component {name} created successfully")


# Task management commands
@task_app.command("status")
def task_status(
    task_id: str = typer.Option(..., "--task-id", "-i", help="Task ID to check status"),
):
    """
    Check the status of an async task
    """
    from celery.result import AsyncResult
    result = AsyncResult(task_id, app=celery_app)
    
    status = result.status
    typer.echo(f"Task ID: {task_id}")
    typer.echo(f"Status: {status}")
    
    if status == 'SUCCESS':
        typer.echo(f"Result: {result.get()}")
    elif status == 'FAILURE':
        typer.echo(f"Error: {result.traceback}")

@task_app.command("list")
def task_list(
    limit: int = typer.Option(10, "--limit", "-n", help="Number of tasks to show"),
    status: Optional[str] = typer.Option(None, "--status", "-s", help="Filter by status (PENDING, SUCCESS, FAILURE)"),
    days: int = typer.Option(1, "--days", "-d", help="Number of days of task history to show"),
):
    """
    List recent async tasks directly from Redis backend
    """
    if not redis_available:
        typer.echo("Redis task backend not available. Cannot list tasks.")
        return
        
    try:
        from redis import Redis
        import json
        from datetime import datetime, timedelta
        
        # Connect to Redis
        redis_client = Redis.from_url(redis_url)
        
        # Find task keys with pattern matching
        task_pattern = "celery-task-meta-*"
        task_keys = redis_client.keys(task_pattern)
        
        if not task_keys:
            typer.echo("No tasks found in the backend.")
            return
            
        # Get task data for each key
        tasks = []
        cutoff_date = datetime.now() - timedelta(days=days)
        
        for key in task_keys:
            try:
                raw_data = redis_client.get(key)
                if not raw_data:
                    continue
                    
                task_data = json.loads(raw_data)
                task_id = key.decode('utf-8').replace('celery-task-meta-', '')
                
                # Add task ID to the data for display
                task_data['task_id'] = task_id
                
                # Parse the received date
                date_str = task_data.get('date_done')
                if date_str:
                    try:
                        task_date = datetime.fromisoformat(date_str)
                        # Skip tasks older than cutoff date
                        if task_date < cutoff_date:
                            continue
                            
                        # Convert to readable format
                        task_data['date_done'] = task_date.strftime("%Y-%m-%d %H:%M:%S")
                    except ValueError:
                        # Keep original if parsing fails
                        pass
                
                # Filter by status if specified
                if status and task_data.get('status') != status:
                    continue
                    
                tasks.append(task_data)
            except Exception as e:
                logger.debug(f"Error parsing task data for {key}: {e}")
                
        # Sort tasks by date (newest first) and limit results
        tasks.sort(key=lambda x: x.get('date_done', ''), reverse=True)
        tasks = tasks[:limit]
        
        # Display tasks in a formatted table
        if tasks:
            typer.echo(f"{'TASK ID':<36} {'STATUS':<10} {'DATE':<20} {'NAME':<30}")
            typer.echo("-" * 96)
            
            for task in tasks:
                task_id = task.get('task_id', 'Unknown')
                task_status = task.get('status', 'Unknown')
                task_date = task.get('date_done', 'Unknown')
                
                # Try to get task name
                task_name = "Unknown"
                if 'result' in task and isinstance(task['result'], dict):
                    if 'task_name' in task['result']:
                        task_name = task['result']['task_name']
                
                typer.echo(f"{task_id:<36} {task_status:<10} {task_date:<20} {task_name:<30}")
        else:
            typer.echo("No matching tasks found.")
            
    except ImportError:
        typer.echo("Required packages not installed. Run 'pip install redis'.")
    except Exception as e:
        typer.echo(f"Error listing tasks: {e}")
        typer.echo("For a more comprehensive task monitoring interface, you can use Celery Flower:")
        typer.echo("1. Install with: pip install flower")
        typer.echo("2. Run with: celery -A gaia.cli.celery_app flower --port=5555")
        typer.echo("3. Visit: http://localhost:5555 for the task dashboard")

@task_app.command("revoke")
def task_revoke(
    task_id: str = typer.Option(..., "--task-id", "-i", help="Task ID to revoke"),
    terminate: bool = typer.Option(False, "--terminate", "-t", help="Terminate the task if it's running"),
):
    """
    Revoke a task (prevent it from starting if it hasn't yet)
    """
    celery_app.control.revoke(task_id, terminate=terminate)
    typer.echo(f"Task {task_id} has been revoked")
    if terminate:
        typer.echo("The task will be terminated if it's currently running")

@task_app.command("purge")
def task_purge(
    force: bool = typer.Option(False, "--force", "-f", help="Force purge without confirmation"),
):
    """
    Purge all pending tasks
    """
    if not force:
        confirm = typer.confirm("Are you sure you want to purge all pending tasks?")
        if not confirm:
            typer.echo("Operation cancelled")
            return
    
    celery_app.control.purge()
    typer.echo("All pending tasks have been purged")


# Certificate Management Commands
@certificate_app.command("rotate")
def cert_rotate(
    secret_name: str = typer.Option(..., "--secret", "-s", help="AWS Secret name in Secrets Manager"),
    namespace: str = typer.Option(..., "--namespace", "-n", help="Kubernetes namespace"),
    acm_cert_arn: Optional[str] = typer.Option(None, "--acm-arn", "-a", help="New AWS ACM Certificate ARN"),
    region: Optional[str] = typer.Option(None, "--region", "-r", help="AWS Region"),
    kube_context: Optional[str] = typer.Option(None, "--context", "-c", help="Kubernetes context"),
    k8s_secret: Optional[str] = typer.Option(None, "--k8s-secret", "-k", help="Kubernetes secret name"),
    profile: Optional[str] = typer.Option(None, "--profile", "-p", help="AWS Profile"),
    private_key_path: Optional[str] = typer.Option(None, "--key-path", help="Path to private key file"),
    auto_restart_pods: bool = typer.Option(False, "--restart-pods", help="Automatically restart pods using the secret"),
    debug: bool = typer.Option(False, "--debug", "-d", help="Enable debug output"),
):
    """
    Rotate a certificate in AWS Secrets Manager and update Kubernetes
    
    This command performs certificate rotation for TLS certificates used in Kubernetes.
    It can update certificates from AWS ACM to Secrets Manager and ensure they are 
    properly synchronized with Kubernetes using External Secrets Operator.
    """
    typer.echo(f"Starting certificate rotation for {secret_name} in {namespace}...")
    
    result = rotate_certificate(
        secret_name=secret_name,
        namespace=namespace,
        acm_cert_arn=acm_cert_arn,
        region=region,
        kube_context=kube_context,
        k8s_secret=k8s_secret,
        profile=profile,
        private_key_path=private_key_path,
        auto_restart_pods=auto_restart_pods,
        debug=debug
    )
    
    if result.get("success", False):
        typer.echo(f"✅ {result.get('message', 'Certificate rotation completed successfully')}")
        return
    else:
        typer.echo(f"❌ {result.get('error', 'Certificate rotation failed')}")
        sys.exit(1)


@workflow_app.command("lint")
def lint(
    fix: bool = typer.Option(False, "--fix", help="Automatically fix issues"),
    skip_security: bool = typer.Option(False, "--skip-security", help="Skip security checks"),
):
    """
    Lint Terraform code and configuration files
    
    Performs formatting checks on Terraform code, YAML linting, and security scanning.
    """
    result = lint_code(fix=fix, skip_security=skip_security)
    
    if not result.get("success"):
        error_msg = result.get("error", result.get("message", "Lint operation failed"))
        typer.echo(f"Error: {error_msg}")
        sys.exit(1)
    
    typer.echo(result.get("message", "Lint operation completed successfully"))


@workflow_app.command("import")
def import_cmd(
    address: str = typer.Option(..., "--address", "-a", help="Terraform resource address (e.g., aws_s3_bucket.bucket)"),
    id: str = typer.Option(..., "--id", "-i", help="Resource ID (e.g., my-bucket-name)"),
    component: str = typer.Option(..., "--component", "-c", help="Component to import the resource into"),
    stack: str = typer.Option(..., "--stack", "-s", help="Stack name (e.g., tenant-account-environment)"),
):
    """
    Import existing resources into Terraform state
    
    Imports resources identified by ID into Terraform state at the specified address.
    """
    result = import_resource(
        resource_address=address,
        resource_id=id,
        component=component,
        stack=stack
    )
    
    if not result.get("success"):
        error_msg = result.get("error", "Import operation failed")
        typer.echo(f"Error: {error_msg}")
        sys.exit(1)
    
    typer.echo(result.get("message", "Import operation completed successfully"))


@workflow_app.command("validate")
def validate(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name"),
    account: str = typer.Option(..., "--account", "-a", help="Account name"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name"),
    skip_lint: bool = typer.Option(False, "--skip-lint", help="Skip linting check"),
    parallel: bool = typer.Option(True, "--parallel", "-p", help="Run validations in parallel"),
    components: List[str] = typer.Option(None, "--component", "-c", help="Specific components to validate"),
):
    """
    Validate Terraform components in a tenant/account/environment
    
    Performs linting and Terraform validation on all components in the specified environment.
    """
    # Skip linting if requested
    if not skip_lint:
        lint_result = lint_code(fix=False, skip_security=False)
        if not lint_result.get("success"):
            error_msg = lint_result.get("error", lint_result.get("message", "Lint check failed"))
            typer.echo(f"Error: {error_msg}")
            typer.echo("Run 'gaia workflow lint --fix' to fix formatting issues.")
            sys.exit(1)
    
    # Run validation
    result = validate_components(
        tenant=tenant,
        account=account,
        environment=environment,
        parallel=parallel,
        components=components
    )
    
    if not result.get("success"):
        error_msg = result.get("error", "Validation failed")
        typer.echo(f"Error: {error_msg}")
        sys.exit(1)
    
    component_count = result.get("components", 0)
    typer.echo(f"Successfully validated {component_count} components")

# Deprecated function removed as part of code cleanup

if __name__ == "__main__":
    app()