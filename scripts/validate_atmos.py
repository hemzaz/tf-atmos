#!/usr/bin/env python3
"""
Atmos Validation Tool

This script performs comprehensive validation of Atmos stacks:
1. Validates YAML syntax for all catalog and environment files
2. Validates catalog structure and component definitions
3. Validates environment imports against the catalog
4. Validates component dependencies are satisfied
5. Runs atmos commands to validate the stack configuration

Requirements:
    - Python 3.6+
    - PyYAML: pip install pyyaml

Usage:
    ./validate_atmos.py [options]

Options:
    -r, --repo-root PATH  Path to repository root (default: current directory)
    -v, --verbose         Enable verbose output
"""

import os
import sys
import re
import subprocess
import yaml
import json
import argparse
from collections import defaultdict
from typing import Dict, List, Set, Any, Tuple, Optional


class AtmosValidator:
    def __init__(self, repo_root: str, verbose: bool = False):
        self.repo_root = repo_root
        self.verbose = verbose
        self.catalog_path = os.path.join(repo_root, "stacks", "catalog")
        self.stacks_path = os.path.join(repo_root, "stacks")
        self.account_path = os.path.join(repo_root, "stacks", "account")
        
        # Track validation results
        self.errors = []
        self.warnings = []
        self.successful_validations = []
        
        # Cache
        self.catalog_components = {}
        self.environment_components = defaultdict(dict)
        self.dependencies = defaultdict(set)

    def log(self, message: str):
        """Log verbose information if enabled"""
        if self.verbose:
            print(f"INFO: {message}")
    
    def validate(self) -> bool:
        """Run all validations and return if successful"""
        self.validate_catalog_yaml()
        self.validate_catalog_structure()
        self.validate_environments()
        self.validate_dependencies()
        self.validate_atmos_commands()
        
        return len(self.errors) == 0

    def report(self):
        """Print validation report"""
        print("\n" + "=" * 80)
        print(" ATMOS VALIDATION REPORT ".center(80, "="))
        print("=" * 80)
        
        # Print successes
        if self.successful_validations:
            print("\n✅ SUCCESSFUL VALIDATIONS:")
            for success in self.successful_validations:
                print(f"  ✓ {success}")
        
        # Print warnings
        if self.warnings:
            print("\n⚠️  WARNINGS:")
            for warning in self.warnings:
                print(f"  ! {warning}")
        
        # Print errors
        if self.errors:
            print("\n❌ ERRORS:")
            for error in self.errors:
                print(f"  ✗ {error}")
        
        # Summary
        print("\n" + "=" * 80)
        print(f"SUMMARY: {'PASSED' if not self.errors else 'FAILED'}")
        print(f"  Successful validations: {len(self.successful_validations)}")
        print(f"  Warnings: {len(self.warnings)}")
        print(f"  Errors: {len(self.errors)}")
        print("=" * 80 + "\n")

    def load_yaml(self, file_path: str) -> Optional[Any]:
        """Load and validate YAML file, return None if invalid"""
        try:
            with open(file_path, 'r') as f:
                return yaml.safe_load(f)
        except yaml.YAMLError as e:
            self.errors.append(f"Invalid YAML in {os.path.relpath(file_path, self.repo_root)}: {str(e)}")
            return None
        except Exception as e:
            self.errors.append(f"Failed to read {os.path.relpath(file_path, self.repo_root)}: {str(e)}")
            return None

    def validate_catalog_yaml(self):
        """Validate all YAML files in the catalog"""
        self.log("Validating YAML syntax in catalog components...")
        valid_count = 0
        invalid_count = 0
        
        for filename in os.listdir(self.catalog_path):
            if not filename.endswith('.yaml'):
                continue
                
            file_path = os.path.join(self.catalog_path, filename)
            component_name = filename[:-5]  # Remove .yaml
            
            yaml_content = self.load_yaml(file_path)
            if yaml_content is not None:
                self.catalog_components[component_name] = yaml_content
                valid_count += 1
            else:
                invalid_count += 1
                
        if invalid_count == 0:
            self.successful_validations.append(f"All {valid_count} catalog YAML files are valid")
        else:
            self.errors.append(f"Found {invalid_count} invalid YAML files in catalog")

    def validate_catalog_structure(self):
        """Validate the structure of catalog components"""
        self.log("Validating catalog component structure...")
        valid_count = 0
        invalid_count = 0
        
        for component_name, content in self.catalog_components.items():
            # Skip if this is just an import of another component
            if "import" in content and "components" not in content:
                valid_count += 1
                continue
                
            if not content or "name" not in content or "components" not in content:
                self.errors.append(f"Catalog component {component_name} missing required fields (name or components)")
                invalid_count += 1
                continue
                
            # Check terraform components section
            if "terraform" not in content.get("components", {}):
                self.warnings.append(f"Catalog component {component_name} has no terraform components")
            
            # Extract dependencies
            for tf_component, tf_config in content.get("components", {}).get("terraform", {}).items():
                if "depends_on" in tf_config:
                    deps = tf_config["depends_on"]
                    if isinstance(deps, list):
                        for dep in deps:
                            self.dependencies[component_name].add(dep)
            
            valid_count += 1
                
        if invalid_count == 0:
            self.successful_validations.append(f"All {valid_count} catalog components have valid structure")

    def find_environments(self) -> List[Tuple[str, str, str]]:
        """Find all environments in the stacks/account directory"""
        environments = []
        
        if os.path.exists(self.account_path):
            for tenant in os.listdir(self.account_path):
                tenant_path = os.path.join(self.account_path, tenant)
                if os.path.isdir(tenant_path):
                    for account in os.listdir(tenant_path):
                        account_path = os.path.join(tenant_path, account)
                        if os.path.isdir(account_path):
                            for env in os.listdir(account_path):
                                env_path = os.path.join(account_path, env)
                                if os.path.isdir(env_path) and os.path.exists(os.path.join(env_path, "main.yaml")):
                                    environments.append((tenant, account, env))
        
        return environments

    def validate_environments(self):
        """Validate all environment stacks"""
        self.log("Validating environment stacks...")
        environments = self.find_environments()
        
        if not environments:
            self.warnings.append("No environments found in stacks/account directory")
            return
            
        for tenant, account, env in environments:
            env_path = os.path.join(self.account_path, tenant, account, env)
            main_file = os.path.join(env_path, "main.yaml")
            
            # Validate main.yaml 
            main_content = self.load_yaml(main_file)
            if not main_content:
                continue
                
            # Check imports
            if "import" not in main_content:
                self.errors.append(f"Environment {tenant}/{account}/{env} main.yaml missing 'import' section")
                continue
                
            # Extract catalog imports
            catalog_imports = []
            for imp in main_content.get("import", []):
                if isinstance(imp, str) and imp.startswith("catalog/"):
                    catalog_imports.append(imp[8:])  # Remove "catalog/" prefix
            
            # Verify all imported components exist in catalog
            missing_imports = []
            for imp in catalog_imports:
                if imp not in self.catalog_components:
                    missing_imports.append(imp)
            
            if missing_imports:
                self.errors.append(f"Environment {tenant}/{account}/{env} imports catalog components that don't exist: {', '.join(missing_imports)}")
            else:
                self.successful_validations.append(f"Environment {tenant}/{account}/{env} imports valid catalog components")
                
            # Check component files in the environment
            for filename in os.listdir(env_path):
                if not filename.endswith('.yaml') or filename in ['main.yaml', 'variables.yaml']:
                    continue
                    
                component_name = filename[:-5]  # Remove .yaml
                component_path = os.path.join(env_path, filename)
                
                # Load and validate the component file
                component_content = self.load_yaml(component_path)
                if component_content:
                    self.environment_components[(tenant, account, env)][component_name] = component_content
                    
                    # Check imports
                    component_imports = []
                    for imp in component_content.get("import", []):
                        if isinstance(imp, str) and imp.startswith("catalog/"):
                            component_imports.append(imp[8:])  # Remove "catalog/" prefix
                    
                    # Verify component's catalog imports exist
                    missing_component_imports = []
                    for imp in component_imports:
                        if imp not in self.catalog_components:
                            missing_component_imports.append(imp)
                    
                    if missing_component_imports:
                        self.errors.append(f"Component {component_name} in {tenant}/{account}/{env} imports catalog components that don't exist: {', '.join(missing_component_imports)}")

    def validate_dependencies(self):
        """Validate that all dependencies are satisfied"""
        self.log("Validating component dependencies...")
        all_dependencies = set()
        missing_dependencies = set()
        
        for component, deps in self.dependencies.items():
            for dep in deps:
                all_dependencies.add(dep)
                if dep not in self.catalog_components:
                    missing_dependencies.add(dep)
        
        if missing_dependencies:
            self.errors.append(f"Missing components required as dependencies: {', '.join(missing_dependencies)}")
        else:
            self.successful_validations.append(f"All {len(all_dependencies)} dependency references are satisfied")

    def run_cmd(self, cmd: List[str]) -> Tuple[int, str, str]:
        """Run a command and return exit code, stdout, stderr"""
        try:
            process = subprocess.Popen(
                cmd, 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = process.communicate()
            return process.returncode, stdout, stderr
        except Exception as e:
            return 1, "", str(e)

    def validate_atmos_commands(self):
        """Validate with atmos CLI commands"""
        self.log("Running atmos validation commands...")
        
        # Check if atmos is available
        exit_code, stdout, stderr = self.run_cmd(["which", "atmos"])
        if exit_code != 0:
            self.warnings.append("Atmos CLI not found in PATH, skipping atmos command validation")
            return
            
        # Run atmos validate stacks to check all stacks
        exit_code, stdout, stderr = self.run_cmd(["atmos", "validate", "stacks"])
        if exit_code == 0:
            self.successful_validations.append("atmos validate stacks command succeeded")
        else:
            self.errors.append(f"atmos validate stacks failed: {stderr.strip()}")

        # Validate specific environments with atmos describe stacks
        environments = self.find_environments()
        for tenant, account, env in environments:
            stack_name = f"{tenant}-{account}-{env}"
            
            exit_code, stdout, stderr = self.run_cmd(["atmos", "describe", "stacks", "-s", stack_name])
            if exit_code == 0:
                self.successful_validations.append(f"Stack {stack_name} validated successfully")
            else:
                self.errors.append(f"Stack {stack_name} validation failed: {stderr.strip()}")


def main():
    """Main entry point for the script"""
    parser = argparse.ArgumentParser(description="Validate Atmos stacks, components, and dependencies")
    parser.add_argument("-r", "--repo-root", default=os.getcwd(), help="Path to repository root (default: current directory)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose output")
    args = parser.parse_args()
    
    # Find repo root - looking for stacks/catalog directory
    repo_root = args.repo_root
    if not os.path.exists(os.path.join(repo_root, "stacks", "catalog")):
        print(f"Error: Could not find stacks/catalog directory in {repo_root}")
        print("Make sure the --repo-root parameter points to the repository root directory")
        sys.exit(1)
    
    # Run validation
    validator = AtmosValidator(repo_root, args.verbose)
    validator.validate()
    validator.report()
    
    # Return exit code
    if validator.errors:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()