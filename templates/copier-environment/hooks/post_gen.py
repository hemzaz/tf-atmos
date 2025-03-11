#!/usr/bin/env python
import os
import sys
import yaml
import shutil
from pathlib import Path
from utility import (
    run_command,
    load_yaml_file,
    is_interactive,
    prompt_continue
)

# Load answers
answers_file = Path('.copier-answers.yml')
if answers_file.exists():
    answers = load_yaml_file(answers_file)
    if not answers:
        print("Error: Could not parse .copier-answers.yml file")
        sys.exit(1)
else:
    print("Error: .copier-answers.yml file not found")
    sys.exit(1)

# Variables from copier
tenant = answers.get('tenant')
account = answers.get('account')
env_name = answers.get('env_name')
env_type = answers.get('env_type')
aws_region = answers.get('aws_region')
eks_cluster = answers.get('eks_cluster')
rds_instances = answers.get('rds_instances')

# Clean up old structure if it exists
old_structure_path = os.path.join("stacks", tenant, account, env_name)
if os.path.exists(old_structure_path):
    print(f"Removing old directory structure: {old_structure_path}")
    shutil.rmtree(old_structure_path)

# Define new structure paths
new_structure_base = os.path.join("stacks", "orgs", tenant, account, aws_region, env_name)
compute_path = os.path.join(new_structure_base, "components", "compute.yaml")
services_path = os.path.join(new_structure_base, "components", "services.yaml")

# Cleanup tasks based on configuration
if not eks_cluster:
    print("EKS cluster disabled, removing EKS configuration files...")
    
    if os.path.exists(compute_path):
        os.remove(compute_path)
        print(f"Removed {compute_path}")
    else:
        print(f"Compute file not found at {compute_path}, skipping removal")

    # If no RDS instances either, remove services.yaml
    if not rds_instances and os.path.exists(services_path):
        os.remove(services_path)
        print(f"Removed {services_path}")

# Create _defaults.yaml files if needed
account_defaults_dir = os.path.join("stacks", "orgs", tenant, account)
account_defaults_file = os.path.join(account_defaults_dir, "_defaults.yaml")

if not os.path.exists(account_defaults_file):
    os.makedirs(os.path.dirname(account_defaults_file), exist_ok=True)
    with open(account_defaults_file, 'w') as f:
        f.write(f"""# Default configuration for {tenant}-{account}
vars:
  tenant: {tenant}
  account: {account}
  
  tags:
    Tenant: {tenant}
    Account: {account}
""")
    print(f"Created {account_defaults_file}")

# Check if atmos is available
try:
    stdout, stderr, code = run_command(["which", "atmos"], check=False)
    
    if code == 0:
        print("\n✅ Atmos detected, validating generated environment...")
        
        # Validate generated environment with Atmos
        stack_name = f"{tenant}-{account}-{aws_region}-{env_name}"
        cmd = [
            "atmos", "validate", "stacks", 
            "--stack", stack_name
        ]
        
        stdout, stderr, code = run_command(cmd, check=False)
        
        if code == 0:
            print("✅ Environment validation successful!")
        else:
            print("⚠️ Environment validation warning. Please review the generated files.")
            print(f"Validation output: {stderr}")
except Exception as e:
    print(f"⚠️ Atmos validation skipped: {str(e)}")

# Print next steps
print("\n=== Environment Generation Complete ===")
print(f"Environment: {tenant}-{account}-{aws_region}-{env_name} ({env_type})")
print("\nNext steps:")
print(f"1. Review generated files in: {os.getcwd()}")
print(f"2. Add the environment to your terraform-atmos repository")
print(f"3. Run: atmos terraform plan vpc -s {tenant}-{account}-{aws_region}-{env_name}")
print(f"4. Run: atmos workflow apply-environment tenant={tenant} account={account} environment={env_name}")
print("\nFor more information, see the environment-templating-guide.md in the docs directory.")