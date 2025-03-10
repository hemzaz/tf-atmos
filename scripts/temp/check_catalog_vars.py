#\!/usr/bin/env python3
import os
import sys
import yaml
import re

CATALOG_DIR = '/Users/elad/IdeaProjects/tf-atmos/stacks/catalog'
REQUIRED_VARS = ['tenant', 'account', 'environment', 'region']
TENANT_VALUE = 'testenv-01'
ACCOUNT_VALUE = 'dev'
ENVIRONMENT_VALUE = 'fnx'
REGION_VALUE = 'eu-west-2'

def load_yaml(file_path):
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            # Handle empty files
            if not content.strip():
                return {}
            return yaml.safe_load(content)
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return {}

def save_yaml(file_path, data):
    with open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

def process_catalog_file(file_path):
    print(f"Processing {file_path}...")
    data = load_yaml(file_path)
    if not data:
        print(f"  Skipping empty or invalid file")
        return False
    
    modified = False
    
    # Check if top-level vars section exists and create if needed
    if 'vars' not in data:
        data['vars'] = {}
        modified = True
    
    # Ensure required variables are present
    for var in REQUIRED_VARS:
        if var not in data['vars']:
            if var == 'tenant':
                data['vars'][var] = '"${tenant}"'
            elif var == 'account':
                data['vars'][var] = '"${account}"'
            elif var == 'environment':
                data['vars'][var] = '"${environment}"'
            elif var == 'region':
                data['vars'][var] = '${region}'
            modified = True
            print(f"  Added missing variable: {var}")
    
    if modified:
        # Convert to YAML, then substitute the variable references back with ${...} format
        yaml_str = yaml.dump(data, default_flow_style=False, sort_keys=False)
        
        # Fix quoted variables (YAML escapes ${...} references)
        yaml_str = re.sub(r'""\$\{([^}]+)\}""', r'"${\\1}"', yaml_str)
        yaml_str = re.sub(r'"\$\{([^}]+)\}"', r'"${\\1}"', yaml_str)
        yaml_str = re.sub(r"''\$\{([^}]+)\}''", r'"${\\1}"', yaml_str)
        yaml_str = re.sub(r"'\$\{([^}]+)\}'", r'"${\\1}"', yaml_str)
        
        # Fix unquoted variables
        yaml_str = re.sub(r'(\s+)(\w+):(\s+)(?<\!")"\$\{([^}]+)\}"(?\!")', r'\1\2:\3${\\4}', yaml_str)
        
        with open(file_path, 'w') as f:
            f.write(yaml_str)
        print(f"  Updated {file_path}")
        return True
    else:
        print(f"  No changes needed")
        return False

def main():
    catalog_files = [os.path.join(CATALOG_DIR, f) for f in os.listdir(CATALOG_DIR) if f.endswith('.yaml')]
    modified_files = []
    
    for file_path in catalog_files:
        if process_catalog_file(file_path):
            modified_files.append(file_path)
    
    if modified_files:
        print(f"\nModified {len(modified_files)} files:")
        for file in modified_files:
            print(f"  - {file}")
    else:
        print("\nNo files needed modification.")

if __name__ == "__main__":
    main()
