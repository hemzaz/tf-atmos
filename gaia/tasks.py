#!/usr/bin/env python3
"""
Celery tasks for Gaia operations
"""

# Removed unused logging import
from typing import List, Optional, Dict, Any

from .cli import celery_app
from .config import AtmosConfig, get_config
from .operations import (
    PlanOperation,
    ApplyOperation,
    ValidateOperation,
    DestroyOperation,
    DriftDetectionOperation
)
from .templating import EnvironmentTemplate
from .templates import ComponentTemplate
from .logger import setup_logger

logger = setup_logger()
# Each task will get its own config instance when needed

@celery_app.task(name="gaia.tasks.plan_environment")
def plan_environment_task(
    tenant: str,
    account: str,
    environment: str,
    components: Optional[List[str]] = None,
    parallel_count: int = 4
) -> bool:
    """
    Celery task for planning environment changes
    """
    logger.info(f"Starting async plan for environment {tenant}-{account}-{environment}")
    config = get_config()
    operation = PlanOperation(config)
    return operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel_count
    )

@celery_app.task(name="gaia.tasks.apply_environment")
def apply_environment_task(
    tenant: str,
    account: str,
    environment: str,
    components: Optional[List[str]] = None,
    parallel_count: int = 4,
    auto_approve: bool = False
) -> bool:
    """
    Celery task for applying environment changes
    """
    logger.info(f"Starting async apply for environment {tenant}-{account}-{environment}")
    config = get_config()
    operation = ApplyOperation(config)
    return operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel_count,
        auto_approve=auto_approve
    )

@celery_app.task(name="gaia.tasks.validate")
def validate_task(
    components: Optional[List[str]] = None,
    parallel_count: int = 8,
) -> bool:
    """
    Celery task for validating components
    """
    logger.info(f"Starting async validation for all components")
    config = get_config()
    operation = ValidateOperation(config)
    return operation.execute_all(
        components=components,
        parallel_count=parallel_count
    )

@celery_app.task(name="gaia.tasks.destroy_environment")
def destroy_environment_task(
    tenant: str,
    account: str,
    environment: str,
    components: Optional[List[str]] = None,
    auto_approve: bool = False
) -> bool:
    """
    Celery task for destroying an environment
    """
    logger.info(f"Starting async destroy for environment {tenant}-{account}-{environment}")
    config = get_config()
    operation = DestroyOperation(config)
    return operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        auto_approve=auto_approve
    )

@celery_app.task(name="gaia.tasks.drift_detection")
def drift_detection_task(
    tenant: str,
    account: str,
    environment: str,
    components: Optional[List[str]] = None,
    parallel_count: int = 4
) -> bool:
    """
    Celery task for drift detection
    """
    logger.info(f"Starting async drift detection for environment {tenant}-{account}-{environment}")
    config = get_config()
    operation = DriftDetectionOperation(config)
    return operation.execute_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        components=components,
        parallel_count=parallel_count
    )

@celery_app.task(name="gaia.tasks.create_environment_template")
def create_environment_template_task(
    tenant: str,
    account: str,
    environment: str,
    **kwargs
) -> bool:
    """
    Celery task for creating an environment from template
    """
    logger.info(f"Starting async environment template creation for {tenant}-{account}-{environment}")
    config = get_config()
    template = EnvironmentTemplate(config)
    return template.create_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        **kwargs
    )

@celery_app.task(name="gaia.tasks.update_environment_template")
def update_environment_template_task(
    tenant: str,
    account: str,
    environment: str,
    **kwargs
) -> bool:
    """
    Celery task for updating an environment from template
    """
    logger.info(f"Starting async environment template update for {tenant}-{account}-{environment}")
    config = get_config()
    template = EnvironmentTemplate(config)
    return template.update_environment(
        tenant=tenant,
        account=account,
        environment=environment,
        **kwargs
    )

@celery_app.task(name="gaia.tasks.create_component")
def create_component_task(
    component_name: str,
    template: str = "terraform-component",
    description: Optional[str] = None,
    destination: Optional[str] = None
) -> bool:
    """
    Celery task for creating a component from template
    """
    logger.info(f"Starting async component creation for {component_name}")
    config = get_config()
    comp_template = ComponentTemplate(config)
    return comp_template.create_component(
        component_name=component_name,
        template=template,
        description=description,
        destination=destination
    )