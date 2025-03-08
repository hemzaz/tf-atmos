#!/usr/bin/env python3
"""
Templating module for Atmos CLI

Provides integration with Copier for environment templating operations.
"""

import os
import sys
import shutil
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple, Union

# Import Copier programmatically
try:
    import copier
except ImportError:
    # Handle this more gracefully in the CLI
    pass

from .config import AtmosConfig
from .logger import setup_logger
from .utils import run_command, is_interactive, prompt_continue

logger = logging.getLogger(__name__)


class TemplateOperation:
    """Base class for template operations"""
    
    def __init__(self, config: AtmosConfig):
        self.config = config
        self.template_dir = self._get_template_dir()
    
    def _get_template_dir(self) -> Path:
        """Get the templates directory path"""
        # First check for project-specific template
        project_templates = Path(self.config.project_root) / "templates"
        if project_templates.exists():
            return project_templates
        
        # Fall back to default template
        atmos_templates = Path(self.config.atmos_root) / "templates"
        if atmos_templates.exists():
            return atmos_templates
        
        # If we can't find templates, log warning
        logger.warning("Could not find templates directory")
        return Path(self.config.project_root) / "templates"
    
    def validate_template_exists(self, template_name: str) -> bool:
        """Check if a template exists"""
        template_path = self.template_dir / template_name
        if not template_path.exists():
            logger.error(f"Template {template_name} not found at {template_path}")
            return False
        return True
    
    def get_available_templates(self) -> List[str]:
        """Get a list of available templates"""
        if not self.template_dir.exists():
            return []
        
        return [
            d.name for d in self.template_dir.iterdir() 
            if d.is_dir() and (d / "copier.yml").exists()
        ]


class EnvironmentTemplate(TemplateOperation):
    """Handles environment templating operations"""
    
    def __init__(self, config: AtmosConfig):
        super().__init__(config)
        self.env_template_dir = self.template_dir / "copier-environment"
    
    def ensure_copier_installed(self) -> bool:
        """Ensure Copier is installed and available"""
        try:
            import copier
            return True
        except ImportError:
            logger.error("Copier is not installed. Please install it with: pip install copier")
            if is_interactive() and prompt_continue("Install Copier now?"):
                result, _, code = run_command([sys.executable, "-m", "pip", "install", "copier"])
                if code == 0:
                    logger.info("Copier installed successfully")
                    # Try importing again
                    try:
                        import copier
                        return True
                    except ImportError:
                        logger.error("Failed to import copier after installation")
                        return False
                else:
                    logger.error(f"Failed to install copier: {result}")
                    return False
            return False
    
    def create_environment(self, 
                          tenant: str, 
                          account: str, 
                          environment: str,
                          env_type: str = None,
                          aws_region: str = None,
                          vpc_cidr: str = None,
                          availability_zones: List[str] = None,
                          team_email: str = None,
                          target_dir: str = None,
                          **kwargs) -> bool:
        """Create a new environment from template"""
        if not self.ensure_copier_installed():
            return False
        
        if not self.validate_template_exists("copier-environment"):
            return False
        
        # Default to project_root/environments/tenant/account/environment
        if not target_dir:
            target_dir = os.path.join(
                self.config.project_root,
                "environments",
                tenant,
                account,
                environment
            )
        
        # Pre-validate to avoid running copier and having it fail
        data = {
            "tenant": tenant,
            "account": account,
            "env_name": environment,
            "env_type": env_type or self._derive_env_type(account),
            "aws_region": aws_region or self._get_default_aws_region(tenant, account, environment),
            "vpc_cidr": vpc_cidr or "10.0.0.0/16",
        }
        
        if availability_zones:
            data["availability_zones"] = availability_zones
        if team_email:
            data["team_email"] = team_email
        
        # Add any additional kwargs
        data.update(kwargs)
        
        # Create the environment using Copier
        try:
            logger.info(f"Creating environment {tenant}-{account}-{environment} at {target_dir}")
            
            # Use Copier programmatically
            import copier
            
            # Run Copier
            copier.run_copy(
                src_path=str(self.env_template_dir),
                dst_path=target_dir,
                data=data,
                vcs_ref="HEAD",
                defaults=True,
                overwrite=True,
                user_defaults=data
            )
            
            logger.info(f"Environment {tenant}-{account}-{environment} created successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create environment: {str(e)}")
            return False
    
    def update_environment(self, 
                           tenant: str, 
                           account: str, 
                           environment: str,
                           target_dir: str = None,
                           **kwargs) -> bool:
        """Update an existing environment from template changes"""
        if not self.ensure_copier_installed():
            return False
        
        if not self.validate_template_exists("copier-environment"):
            return False
        
        # Default to project_root/environments/tenant/account/environment
        if not target_dir:
            target_dir = os.path.join(
                self.config.project_root,
                "environments",
                tenant,
                account,
                environment
            )
        
        # Verify the target directory exists
        if not os.path.exists(target_dir):
            logger.error(f"Environment directory {target_dir} does not exist")
            return False
        
        # Add any additional kwargs
        data = kwargs.copy()
        
        # Update the environment using Copier
        try:
            logger.info(f"Updating environment {tenant}-{account}-{environment} at {target_dir}")
            
            # Use Copier programmatically
            import copier
            
            # Run Copier update
            copier.run_update(
                dst_path=target_dir,
                vcs_ref="HEAD",
                defaults=True,
                overwrite=kwargs.get('overwrite', False),
                user_defaults=data
            )
            
            logger.info(f"Environment {tenant}-{account}-{environment} updated successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to update environment: {str(e)}")
            return False
    
    def _derive_env_type(self, account: str) -> str:
        """Derive environment type from account name"""
        if account in ['prod', 'production']:
            return 'production'
        elif account in ['staging', 'stage']:
            return 'staging'
        else:
            return 'development'
    
    def _get_default_aws_region(self, tenant: str = None, account: str = None, environment: str = None) -> str:
        """
        Get default AWS region with the following precedence:
        1. Environment main.yaml file (if tenant, account, environment provided)
        2. Environment variables (AWS_REGION or AWS_DEFAULT_REGION)
        3. AWS CLI configuration
        4. Project default (us-west-2)
        """
        # First, try to read from environment main.yaml if info is provided
        if tenant and account and environment:
            try:
                # Check if the environment already exists and has a main.yaml file
                main_yaml_path = os.path.join(
                    self.config.project_root,
                    "stacks",
                    tenant,
                    account,
                    environment,
                    "main.yaml"
                )
                
                # If file exists, try to parse it and get the region
                import yaml
                if os.path.exists(main_yaml_path):
                    with open(main_yaml_path, 'r') as file:
                        yaml_content = yaml.safe_load(file)
                        # Look for region in the YAML structure
                        if yaml_content and isinstance(yaml_content, dict):
                            # Check various locations where region might be defined
                            if 'region' in yaml_content:
                                logger.info(f"Using region from main.yaml: {yaml_content['region']}")
                                return yaml_content['region']
                            if 'vars' in yaml_content and 'region' in yaml_content['vars']:
                                logger.info(f"Using region from main.yaml vars: {yaml_content['vars']['region']}")
                                return yaml_content['vars']['region']
                            if 'terraform' in yaml_content and 'vars' in yaml_content['terraform'] and 'region' in yaml_content['terraform']['vars']:
                                logger.info(f"Using region from terraform vars: {yaml_content['terraform']['vars']['region']}")
                                return yaml_content['terraform']['vars']['region']
            except Exception as e:
                logger.debug(f"Could not read region from main.yaml: {str(e)}")
        
        # Check environment variables
        if 'AWS_REGION' in os.environ:
            logger.info(f"Using region from AWS_REGION: {os.environ['AWS_REGION']}")
            return os.environ['AWS_REGION']
        if 'AWS_DEFAULT_REGION' in os.environ:
            logger.info(f"Using region from AWS_DEFAULT_REGION: {os.environ['AWS_DEFAULT_REGION']}")
            return os.environ['AWS_DEFAULT_REGION']
        
        # Try to get from AWS CLI
        try:
            stdout, _, code = run_command(['aws', 'configure', 'get', 'region'])
            if code == 0 and stdout.strip():
                logger.info(f"Using region from AWS CLI config: {stdout.strip()}")
                return stdout.strip()
        except Exception:
            pass
        
        # Default fallback
        logger.info("Using default region: us-west-2")
        return 'us-west-2'