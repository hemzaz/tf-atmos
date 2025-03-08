#!/usr/bin/env python
"""Utility functions for Copier hooks"""

import os
import re
import sys
import ipaddress
import json
import yaml
import subprocess
from typing import List, Dict, Any, Tuple, Optional


def is_ci_environment() -> bool:
    """Check if running in a CI/CD environment"""
    ci_vars = ['CI', 'GITHUB_ACTIONS', 'GITLAB_CI', 'TF_BUILD', 'JENKINS_URL']
    return any(var in os.environ for var in ci_vars)


def is_interactive() -> bool:
    """Check if running in an interactive terminal"""
    return sys.stdin.isatty() and not is_ci_environment()


def prompt_continue(message: str) -> bool:
    """Prompt user to continue, return False to abort"""
    print(message)
    
    if not is_interactive():
        print("Running in non-interactive mode, continuing despite warning...")
        return True
    
    response = input("Continue anyway? (y/n): ")
    return response.lower() == 'y'


def run_command(command: List[str], check: bool = True) -> Tuple[str, str, int]:
    """Run a command and return stdout, stderr, and return code"""
    try:
        result = subprocess.run(
            command,
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.CalledProcessError as e:
        if check:
            print(f"Command failed: {' '.join(command)}")
            print(f"Error: {e.stderr}")
            sys.exit(1)
        return "", e.stderr, e.returncode


def validate_cidr(cidr: str) -> bool:
    """Validate CIDR block format"""
    try:
        ipaddress.ip_network(cidr)
        return True
    except ValueError:
        print(f"Error: Invalid CIDR format: {cidr}")
        print("Expected format: x.x.x.x/y (e.g., 10.0.0.0/16)")
        return False


def validate_environment_name(name: str, strict: bool = False) -> bool:
    """Validate environment name format"""
    # Basic validation - must be valid identifier
    if not re.match(r'^[a-zA-Z0-9][\-a-zA-Z0-9]*$', name):
        print("Error: Environment name must be a valid identifier starting with a letter or number")
        return False
    
    # Pattern validation - recommended to follow name-## pattern
    if not re.match(r'^[a-z0-9]+-[0-9]{2}$', name):
        print("Warning: Environment name doesn't follow recommended pattern: name-##")
        print("This pattern helps with consistent naming across environments.")
        
        # If strict mode, return False
        if strict:
            return False
        
        # In interactive mode, ask for confirmation
        if not prompt_continue("Using a non-standard name format may lead to inconsistencies."):
            return False
    
    return True


def validate_availability_zones(azs: List[str], region: str) -> bool:
    """Validate availability zones match the region"""
    for az in azs:
        if not az.startswith(region):
            print(f"Error: Availability zone {az} does not match region {region}")
            return False
    return True


def validate_environment_consistency(env_type: str, account: str) -> bool:
    """Validate environment type matches account name"""
    if env_type == "production" and account != "prod":
        print("Warning: Production environment type selected, but account is not 'prod'")
        print("This may lead to inconsistent configuration. Consider changing account to 'prod'")
        
        if not prompt_continue("Using inconsistent naming may lead to confusion."):
            return False
    
    return True


def validate_email(email: str) -> bool:
    """Validate email address format"""
    if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email):
        print(f"Error: Invalid email format: {email}")
        return False
    
    if email.endswith("example.com"):
        print(f"Warning: Using example email address: {email}")
        if not prompt_continue("This appears to be an example email - it should be updated for production use."):
            return False
    
    return True


def load_yaml_file(file_path: str) -> Optional[Dict[str, Any]]:
    """Load YAML file safely"""
    try:
        with open(file_path, 'r') as file:
            return yaml.safe_load(file)
    except (yaml.YAMLError, FileNotFoundError) as e:
        print(f"Error loading YAML file {file_path}: {e}")
        return None


def write_yaml_file(file_path: str, data: Dict[str, Any]) -> bool:
    """Write data to YAML file"""
    try:
        with open(file_path, 'w') as file:
            yaml.safe_dump(data, file, default_flow_style=False)
        return True
    except Exception as e:
        print(f"Error writing YAML file {file_path}: {e}")
        return False


def detect_aws_region() -> str:
    """Detect AWS region from environment or fall back to default"""
    # Check environment variables
    if 'AWS_REGION' in os.environ:
        return os.environ['AWS_REGION']
    if 'AWS_DEFAULT_REGION' in os.environ:
        return os.environ['AWS_DEFAULT_REGION']
    
    # Try to get from AWS CLI
    try:
        stdout, _, code = run_command(['aws', 'configure', 'get', 'region'], check=False)
        if code == 0 and stdout.strip():
            return stdout.strip()
    except Exception:
        pass
    
    # Default fallback
    return 'us-west-2'