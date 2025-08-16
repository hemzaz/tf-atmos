#!/usr/bin/env python3
"""
Validate that all catalog files have a tenant value defined
"""

import os
import sys
import yaml
import glob
from pprint import pprint

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_DIR = os.path.join(REPO_ROOT, "stacks", "catalog")

def process_yaml_file(file_path):
    """Process a YAML file and check for tenant"""
    try:
        with open(file_path, 'r') as f:
            content = yaml.safe_load(f)
            
        file_name = os.path.basename(file_path)
        component_name = os.path.splitext(file_name)[0]
        
        # Check if the file has a name field
        if not content.get('name'):
            return (file_name, False, "Missing 'name' field")
        
        # Check if there's a vars section with tenant
        if 'vars' in content and 'tenant' in content['vars']:
            return (file_name, True, f"Tenant defined: {content['vars']['tenant']}")
            
        # Check component-level vars with tenant
        for component_type, components in content.get('components', {}).items():
            for component_name, component_config in components.items():
                if 'vars' in component_config and 'tenant' in component_config['vars']:
                    return (file_name, True, f"Tenant defined in component {component_name}")
        
        return (file_name, False, "No tenant defined in file")
    
    except yaml.YAMLError as e:
        return (file_path, False, f"YAML parsing error: {str(e)}")
    except Exception as e:
        return (file_path, False, f"Error processing file: {str(e)}")

def add_tenant_to_file(file_path):
    """Add tenant value to a YAML file"""
    try:
        with open(file_path, 'r') as f:
            content = yaml.safe_load(f)
            
        # Simple case: add to top-level vars
        if 'vars' in content:
            content['vars']['tenant'] = "${tenant}"
        # More complex case: add to each component's vars
        elif 'components' in content:
            for component_type, components in content['components'].items():
                for component_name, component_config in components.items():
                    if 'vars' in component_config:
                        component_config['vars']['tenant'] = "${tenant}"
        
        with open(file_path, 'w') as f:
            yaml.dump(content, f, default_flow_style=False)
        
        return True
    except Exception as e:
        print(f"Error updating file {file_path}: {str(e)}")
        return False

def main():
    """Main function"""
    catalog_files = glob.glob(os.path.join(CATALOG_DIR, "*.yaml"))
    
    if not catalog_files:
        print(f"No catalog files found in {CATALOG_DIR}")
        return
    
    print(f"Found {len(catalog_files)} catalog files")
    
    # Process each file
    results = []
    for file_path in catalog_files:
        result = process_yaml_file(file_path)
        results.append(result)
    
    # Print summary
    missing_tenant = []
    has_tenant = []
    
    for file_name, has_tenant_value, message in results:
        if has_tenant_value:
            has_tenant.append((file_name, message))
        else:
            missing_tenant.append((file_name, message))
    
    print("\n=== Files with tenant defined ===")
    for file_name, message in has_tenant:
        print(f"✅ {file_name}: {message}")
    
    print("\n=== Files missing tenant ===")
    for file_name, message in missing_tenant:
        print(f"❌ {file_name}: {message}")
    
    print(f"\nSummary: {len(has_tenant)} files have tenant, {len(missing_tenant)} files are missing tenant")
    
    # Ask if user wants to fix missing tenant
    if missing_tenant and input("\nWould you like to add tenant to files missing it? (y/n): ").lower() == 'y':
        fixed_count = 0
        for file_name, _ in missing_tenant:
            file_path = os.path.join(CATALOG_DIR, file_name)
            if add_tenant_to_file(file_path):
                fixed_count += 1
                print(f"Fixed {file_name}")
        
        print(f"\nFixed {fixed_count} of {len(missing_tenant)} files")

if __name__ == "__main__":
    main()