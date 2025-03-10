#!/usr/bin/env python3
"""
Add tenant to all Terraform components in catalog files
"""

import os
import sys
import yaml
import glob
from pprint import pprint

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_DIR = os.path.join(REPO_ROOT, "stacks", "catalog")

def safe_yaml_load(file_path):
    """Load YAML file safely"""
    try:
        with open(file_path, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"Error loading {file_path}: {str(e)}")
        return None

def safe_yaml_dump(content, file_path):
    """Dump YAML content safely"""
    try:
        with open(file_path, 'w') as f:
            yaml.dump(content, f, default_flow_style=False, sort_keys=False)
        return True
    except Exception as e:
        print(f"Error writing to {file_path}: {str(e)}")
        return False

def add_tenant_to_component(component):
    """Add tenant to a component's vars"""
    if 'vars' not in component:
        component['vars'] = {}
    
    if 'tenant' not in component['vars']:
        component['vars']['tenant'] = "${tenant}"
        return True
    return False

def process_catalog_file(file_path):
    """Process a catalog file to add tenant to components"""
    content = safe_yaml_load(file_path)
    if not content:
        return False
    
    modified = False
    
    # Add tenant to each Terraform component
    if 'components' in content and 'terraform' in content['components']:
        for component_name, component in content['components']['terraform'].items():
            if add_tenant_to_component(component):
                modified = True
                print(f"  Added tenant to component '{component_name}'")
    
    if modified:
        if safe_yaml_dump(content, file_path):
            print(f"✅ Updated {os.path.basename(file_path)}")
            return True
        else:
            print(f"❌ Failed to write to {os.path.basename(file_path)}")
            return False
    
    print(f"ℹ️ No changes needed for {os.path.basename(file_path)}")
    return False

def main():
    """Main function"""
    catalog_files = glob.glob(os.path.join(CATALOG_DIR, "*.yaml"))
    
    if not catalog_files:
        print(f"No catalog files found in {CATALOG_DIR}")
        return
    
    print(f"Found {len(catalog_files)} catalog files")
    
    # Process each file
    modified_count = 0
    for file_path in sorted(catalog_files):
        print(f"\nProcessing {os.path.basename(file_path)}...")
        if process_catalog_file(file_path):
            modified_count += 1
    
    print(f"\nSummary: Modified {modified_count} of {len(catalog_files)} files")

if __name__ == "__main__":
    main()