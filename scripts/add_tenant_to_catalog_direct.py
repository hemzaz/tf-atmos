#!/usr/bin/env python3
"""
Add tenant directly to all catalog files without dependencies
"""

import os
import sys
import glob
import json

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_DIR = os.path.join(REPO_ROOT, "stacks", "catalog")

def read_file(file_path):
    """Read file content"""
    try:
        with open(file_path, 'r') as f:
            return f.read()
    except Exception as e:
        print(f"Error reading {file_path}: {str(e)}")
        return None

def write_file(file_path, content):
    """Write content to file"""
    try:
        with open(file_path, 'w') as f:
            f.write(content)
        return True
    except Exception as e:
        print(f"Error writing to {file_path}: {str(e)}")
        return False

def add_tenant_to_file(file_path):
    """Add tenant to a YAML file using direct text insertion"""
    content = read_file(file_path)
    if not content:
        return False
    
    file_name = os.path.basename(file_path)
    
    # Check if tenant is already defined
    if 'tenant: ' in content or 'tenant:${' in content or 'tenant: ${' in content:
        print(f"ℹ️ {file_name} already has tenant - skipping")
        return False
    
    # Look for components.terraform section
    modified = False
    lines = content.splitlines()
    output_lines = []
    in_vars_section = False
    found_components_terraform = False
    
    for i, line in enumerate(lines):
        output_lines.append(line)
        
        # Simple case - add to top-level vars section
        if line.strip() == 'vars:':
            in_vars_section = True
            continue
            
        if in_vars_section and line.strip() and not line.startswith(' '):
            in_vars_section = False
            
        # Add tenant to component vars sections
        if line.strip() == 'components:':
            found_components_terraform = True
            
        if found_components_terraform and line.strip() == 'vars:' and i > 0 and '  terraform:' in lines[i-10:i]:
            # Found vars section in a terraform component
            # Check indentation level
            indent = len(line) - len(line.lstrip())
            # Add tenant to this vars section
            output_lines.append(' ' * indent + '  tenant: "${tenant}"')
            modified = True
    
    if not modified:
        print(f"⚠️ {file_name} - couldn't find appropriate place to add tenant")
        return False
    
    # Write modified content back to file
    if write_file(file_path, '\n'.join(output_lines)):
        print(f"✅ Added tenant to {file_name}")
        return True
    else:
        print(f"❌ Failed to update {file_name}")
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
        print(f"Processing {os.path.basename(file_path)}...")
        if add_tenant_to_file(file_path):
            modified_count += 1
    
    print(f"\nSummary: Modified {modified_count} of {len(catalog_files)} files")

if __name__ == "__main__":
    main()