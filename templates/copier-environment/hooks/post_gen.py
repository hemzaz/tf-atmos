#!/usr/bin/env python
import os
import sys
import yaml
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
eks_cluster = answers.get('eks_cluster')
rds_instances = answers.get('rds_instances')

# Cleanup tasks based on configuration
if not eks_cluster:
    print("EKS cluster disabled, removing EKS configuration files...")
    
    eks_yaml_path = os.path.join(
        "stacks", tenant, account, env_name, "eks.yaml"
    )
    if os.path.exists(eks_yaml_path):
        os.remove(eks_yaml_path)
        print(f"Removed {eks_yaml_path}")
    else:
        print(f"EKS config file not found at {eks_yaml_path}, skipping removal")

if not rds_instances:
    print("RDS instances disabled, removing RDS configuration files...")
    
    rds_yaml_path = os.path.join(
        "stacks", tenant, account, env_name, "rds.yaml"
    )
    if os.path.exists(rds_yaml_path):
        os.remove(rds_yaml_path)
        print(f"Removed {rds_yaml_path}")
    else:
        print(f"RDS config file not found at {rds_yaml_path}, skipping removal")

# Check if atmos is available
try:
    stdout, stderr, code = run_command(["which", "atmos"], check=False)
    
    if code == 0:
        print("\n✅ Atmos detected, validating generated environment...")
        
        # Validate generated environment with Atmos
        cmd = [
            "atmos", "validate", "stacks", 
            "--stack", f"{tenant}-{account}-{env_name}"
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
print(f"Environment: {tenant}-{account}-{env_name} ({env_type})")
print("\nNext steps:")
print(f"1. Review generated files in: {os.getcwd()}")
print(f"2. Add the environment to your terraform-atmos repository")
print(f"3. Run: atmos terraform plan vpc -s {tenant}-{account}-{env_name}")
print(f"4. Run: atmos workflow apply-environment tenant={tenant} account={account} environment={env_name}")
print("\nFor more information, see the environment-templating-guide.md in the docs directory.")