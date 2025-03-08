"""
Configuration management for Atmos CLI.
Handles loading of environment variables, config files, and defaults.
"""

import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Any
import subprocess
from dataclasses import dataclass, field
import dotenv
import yaml
# semver import removed (unused)
from pydantic import BaseModel

from gaia.logger import get_logger

logger = get_logger(__name__)


class VersionConfig(BaseModel):
    """Configuration for tool versions used in Atmos."""
    terraform: str = "1.5.7"
    atmos: str = "1.38.0"
    kubectl: str = "1.28.3"
    helm: str = "3.13.1"
    tfsec: str = "1.28.13"
    tflint: str = "0.55.1"
    checkov: str = "3.2.382"
    copier: str = "9.5.0"
    terraform_docs: str = "0.16.0"


class PathConfig(BaseModel):
    """Configuration for paths used in Atmos."""
    components_dir: str = "components/terraform"
    scripts_dir: str = "scripts"
    workflows_dir: str = "workflows"
    stacks_base_dir: str = "stacks"


@dataclass
class AtmosConfig:
    """Atmos configuration class."""
    versions: VersionConfig = field(default_factory=VersionConfig)
    paths: PathConfig = field(default_factory=PathConfig)
    repo_root: Path = field(default_factory=lambda: get_repo_root())
    
    # Task execution settings
    async_mode: bool = False
    redis_url: str = "redis://localhost:6379/0"
    celery_workers: int = 4
    
    # Additional configuration values stored as a dictionary
    values: Dict[str, Any] = field(default_factory=dict)
    
    def __post_init__(self):
        """Initialize paths relative to repository root."""
        self.paths.components_dir = str(self.repo_root / self.paths.components_dir)
        self.paths.scripts_dir = str(self.repo_root / self.paths.scripts_dir)
        self.paths.workflows_dir = str(self.repo_root / self.paths.workflows_dir)
        self.paths.stacks_base_dir = str(self.repo_root / self.paths.stacks_base_dir)
    
    def get_env_dir(self, tenant: str, account: str, environment: str) -> Path:
        """Get the environment directory path."""
        env_dir = Path(self.paths.stacks_base_dir) / tenant / account / environment
        
        if not env_dir.exists():
            logger.error(f"Environment directory does not exist: {env_dir}")
            raise FileNotFoundError(f"Environment directory does not exist: {env_dir}")
        
        return env_dir
    
    def check_cli_versions(self) -> Dict[str, Dict[str, str]]:
        """Check installed CLI tools against required versions."""
        results = {}
        
        # Check Atmos CLI version
        if atmos_path := find_executable("atmos"):
            try:
                version_output = subprocess.check_output([atmos_path, "version"], 
                                                         text=True, stderr=subprocess.STDOUT)
                
                version_match = re.search(r'Atmos (\d+\.\d+\.\d+)', version_output)
                if version_match:
                    installed_version = version_match.group(1)
                    logger.info(f"Using Atmos CLI version: {installed_version}")
                    
                    required_version = self.versions.atmos
                    if installed_version != required_version:
                        logger.warning(
                            f"Installed Atmos version ({installed_version}) doesn't match " 
                            f"required version ({required_version})")
                    
                    results["atmos"] = {
                        "installed": installed_version,
                        "required": required_version,
                        "match": installed_version == required_version
                    }
            except subprocess.CalledProcessError as e:
                logger.error(f"Error checking Atmos version: {e}")
        
        # Additional CLI tool checks can be added here for terraform, kubectl, etc.
        
        return results


def get_repo_root() -> Path:
    """Find the repository root directory."""
    try:
        repo_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], 
            text=True, stderr=subprocess.DEVNULL
        ).strip()
        return Path(repo_root)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd()


def find_executable(name: str) -> Optional[str]:
    """Find an executable in PATH."""
    for path in os.environ.get("PATH", "").split(os.pathsep):
        executable = Path(path) / name
        if executable.exists() and os.access(executable, os.X_OK):
            return str(executable)
    return None


def find_config_files() -> List[Path]:
    """Find configuration files in order of precedence."""
    repo_root = get_repo_root()
    config_paths = [
        # Explicit environment variable
        os.environ.get("ATMOS_CONFIG_FILE"),
        # Project-specific configs
        repo_root / ".atmos.env",
        repo_root / ".env",
        # User-specific configs
        Path.home() / ".atmos" / "config",
        Path.home() / ".config" / "atmos" / "config",
    ]
    
    # Filter out None values and non-existent files
    return [path for path in config_paths if path and Path(path).is_file()]


def load_yaml_config(file_path: Path) -> Dict[str, Any]:
    """Load configuration from YAML file."""
    try:
        with open(file_path, 'r') as f:
            return yaml.safe_load(f) or {}
    except (yaml.YAMLError, OSError) as e:
        logger.error(f"Error loading YAML config from {file_path}: {e}")
        return {}


def load_env_config(file_path: Path) -> Dict[str, str]:
    """Load configuration from .env file."""
    try:
        return dotenv.dotenv_values(file_path)
    except Exception as e:
        logger.error(f"Error loading env config from {file_path}: {e}")
        return {}


def load_config() -> AtmosConfig:
    """Load Atmos configuration from all sources."""
    config = AtmosConfig()
    config_files = find_config_files()
    
    if not config_files:
        logger.warning("No configuration files found. Using default values.")
        return config
    
    # Process config files in reverse order (lowest precedence first)
    for file_path in reversed(config_files):
        file_path = Path(file_path)
        logger.info(f"Loading configuration from {file_path}")
        
        if file_path.suffix in ['.yaml', '.yml']:
            yaml_config = load_yaml_config(file_path)
            
            # Update version configs if present
            if 'versions' in yaml_config:
                for key, value in yaml_config['versions'].items():
                    if hasattr(config.versions, key):
                        setattr(config.versions, key, value)
            
            # Update path configs if present
            if 'paths' in yaml_config:
                for key, value in yaml_config['paths'].items():
                    if hasattr(config.paths, key):
                        setattr(config.paths, key, value)
            
            # Store other values
            for key, value in yaml_config.items():
                if key not in ['versions', 'paths']:
                    config.values[key] = value
                    
        else:
            # Handle .env files
            env_config = load_env_config(file_path)
            
            # Update tool versions
            for key in ['TERRAFORM_VERSION', 'ATMOS_VERSION', 'KUBECTL_VERSION',
                        'HELM_VERSION', 'TFSEC_VERSION', 'TFLINT_VERSION',
                        'CHECKOV_VERSION', 'COPIER_VERSION', 'TERRAFORM_DOCS_VERSION']:
                if key in env_config:
                    attr_name = key.replace('_VERSION', '').lower()
                    if hasattr(config.versions, attr_name):
                        setattr(config.versions, attr_name, env_config[key])
            
            # Update paths
            for key in ['COMPONENTS_DIR', 'SCRIPTS_DIR', 'WORKFLOWS_DIR', 'STACKS_BASE_DIR']:
                if key in env_config:
                    attr_name = key.lower()
                    if hasattr(config.paths, attr_name):
                        setattr(config.paths, attr_name, env_config[key])
            
            # Update task execution settings
            if 'ASYNC_MODE' in env_config:
                config.async_mode = env_config['ASYNC_MODE'].lower() in ('true', 'yes', '1')
            if 'REDIS_URL' in env_config:
                config.redis_url = env_config['REDIS_URL']
            if 'CELERY_WORKERS' in env_config:
                try:
                    config.celery_workers = int(env_config['CELERY_WORKERS'])
                except ValueError:
                    logger.warning(f"Invalid CELERY_WORKERS value: {env_config['CELERY_WORKERS']}")
                    
            
            # Store other values
            for key, value in env_config.items():
                if not key.endswith('_VERSION') and key not in ['COMPONENTS_DIR', 'SCRIPTS_DIR', 
                                                               'WORKFLOWS_DIR', 'STACKS_BASE_DIR']:
                    config.values[key] = value
    
    # Initialize paths relative to repo root
    config.__post_init__()
    
    return config


# Global configuration instance
_config: Optional[AtmosConfig] = None

def get_config() -> AtmosConfig:
    """Get the global configuration instance."""
    global _config
    if _config is None:
        _config = load_config()
    return _config