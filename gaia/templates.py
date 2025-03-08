#!/usr/bin/env python3
"""
Templates module for Atmos CLI

Contains functions and classes for managing templates.
"""

import os
import json
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional

from .config import AtmosConfig

logger = logging.getLogger(__name__)

class TemplateManager:
    """Base class for template management"""
    
    def __init__(self, config: AtmosConfig):
        self.config = config
        self.templates_dir = Path(self.config.project_root) / "templates"
    
    def get_available_templates(self) -> List[str]:
        """Get a list of available templates"""
        if not self.templates_dir.exists():
            return []
        
        # Get all directories that have copier.yml (for copier templates)
        copier_templates = [
            d.name for d in self.templates_dir.iterdir()
            if d.is_dir() and (d / "copier.yml").exists()
        ]
        
        # Get all directories that have catalog-info.yaml (for component templates)
        catalog_templates = [
            str(f.relative_to(self.templates_dir)) 
            for f in self.templates_dir.glob('**/catalog-info.yaml')
        ]
        
        return sorted(set(copier_templates + catalog_templates))
    
    def get_template_path(self, template_name: str) -> Optional[Path]:
        """Get the path for a template"""
        template_path = self.templates_dir / template_name
        
        if template_path.exists():
            return template_path
        
        # Try to find it as a catalog template (might be nested)
        for path in self.templates_dir.glob('**/catalog-info.yaml'):
            if template_name in str(path.relative_to(self.templates_dir)):
                return path.parent
        
        return None
    
    def validate_template_exists(self, template_name: str) -> bool:
        """Check if a template exists"""
        template_path = self.get_template_path(template_name)
        if not template_path:
            logger.error(f"Template {template_name} not found")
            return False
        return True


class ComponentTemplate(TemplateManager):
    """Component template manager"""
    
    def list_component_templates(self) -> List[Dict[str, Any]]:
        """List available component templates with metadata"""
        templates = []
        
        # Check for component templates
        if not self.templates_dir.exists():
            return []
            
        # Look for terraform-component templates
        component_template_path = self.templates_dir / "terraform-component"
        if component_template_path.exists():
            templates.append({
                "name": "terraform-component",
                "type": "terraform",
                "description": "Standard Terraform component template",
                "path": str(component_template_path)
            })
            
        # Look for catalog components
        for catalog_file in self.templates_dir.glob('**/catalog-info.yaml'):
            try:
                # Parse catalog YAML
                with open(catalog_file, 'r') as f:
                    import yaml
                    catalog_data = yaml.safe_load(f)
                    
                templates.append({
                    "name": catalog_data.get("metadata", {}).get("name", catalog_file.parent.name),
                    "type": catalog_data.get("kind", "Component"),
                    "description": catalog_data.get("metadata", {}).get("description", ""),
                    "path": str(catalog_file.parent)
                })
            except Exception as e:
                logger.warning(f"Error parsing catalog file {catalog_file}: {e}")
                
        return templates
    
    def create_component(self, 
                        component_name: str,
                        template: str = "terraform-component",
                        description: str = None,
                        destination: str = None) -> bool:
        """Create a new component from template"""
        # Validate template exists
        template_path = self.get_template_path(template)
        if not template_path:
            logger.error(f"Template {template} not found")
            return False
            
        # Determine destination
        if not destination:
            destination = Path(self.config.project_root) / "components" / component_name
        else:
            destination = Path(destination)
            
        # Create destination directory if it doesn't exist
        destination.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Creating component {component_name} from template {template}")
        
        try:
            # Copy template files
            import shutil
            
            # Check if we're using Copier
            if (template_path / "copier.yml").exists():
                try:
                    import copier
                    
                    copier.run_copy(
                        src_path=str(template_path),
                        dst_path=str(destination),
                        data={
                            "component_name": component_name,
                            "description": description or f"{component_name} component"
                        },
                        vcs_ref="HEAD",
                        defaults=True,
                        overwrite=True
                    )
                except ImportError:
                    logger.warning("Copier not installed, falling back to simple file copy")
                    self._copy_files(template_path, destination, component_name, description)
            else:
                # Simple file copy
                self._copy_files(template_path, destination, component_name, description)
                
            logger.info(f"Component {component_name} created at {destination}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create component: {e}")
            return False
    
    def _copy_files(self, 
                   source_path: Path, 
                   destination: Path,
                   component_name: str,
                   description: str = None) -> None:
        """Copy files from template to destination with basic templating"""
        import shutil
        import re
        
        for item in source_path.glob('**/*'):
            # Skip directories, they'll be created as needed
            if item.is_dir():
                continue
                
            # Skip .git and other hidden files
            if any(part.startswith('.') for part in item.parts):
                continue
                
            # Calculate relative path
            rel_path = item.relative_to(source_path)
            
            # Replace placeholders in the path
            path_str = str(rel_path)
            path_str = path_str.replace("{{component_name}}", component_name)
            
            # Create destination file path
            dest_file = destination / path_str
            
            # Create parent directories if they don't exist
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Copy the file
            try:
                # For text files, do basic templating
                if self._is_text_file(item):
                    with open(item, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # Replace placeholders
                    content = content.replace("{{component_name}}", component_name)
                    if description:
                        content = content.replace(
                            "{{description}}", 
                            description
                        )
                    else:
                        content = content.replace(
                            "{{description}}", 
                            f"{component_name} component"
                        )
                    
                    # Write the file
                    with open(dest_file, 'w', encoding='utf-8') as f:
                        f.write(content)
                else:
                    # For binary files, just copy
                    shutil.copy2(item, dest_file)
            except Exception as e:
                logger.warning(f"Error copying {item} to {dest_file}: {e}")
    
    def _is_text_file(self, file_path: Path) -> bool:
        """Check if a file is a text file"""
        # Common text file extensions
        text_extensions = {
            '.tf', '.tfvars', '.hcl', '.json', '.yaml', '.yml', '.md', 
            '.txt', '.sh', '.py', '.rb', '.js', '.css', '.html'
        }
        
        # Check extension
        if file_path.suffix in text_extensions:
            return True
            
        # Try reading as text
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                f.read(1024)  # Read a bit to check if it's text
            return True
        except UnicodeDecodeError:
            return False