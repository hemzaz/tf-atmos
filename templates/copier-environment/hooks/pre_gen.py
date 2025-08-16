#!/usr/bin/env python
import sys
import yaml
from pathlib import Path
from utility import (
    validate_cidr,
    validate_environment_name,
    validate_availability_zones,
    validate_environment_consistency,
    validate_email
)

# Load answers
answers_file = Path('.copier-answers.yml')
if answers_file.exists():
    with open(answers_file, 'r') as f:
        answers = yaml.safe_load(f)
else:
    print("Error: .copier-answers.yml file not found")
    sys.exit(1)

# Extract key values
vpc_cidr = answers.get('vpc_cidr')
env_name = answers.get('env_name')
aws_region = answers.get('aws_region')
availability_zones = answers.get('availability_zones')
env_type = answers.get('env_type')
account = answers.get('account')
team_email = answers.get('team_email')

# Perform validations
if not validate_cidr(vpc_cidr):
    sys.exit(1)

if not validate_environment_name(env_name):
    sys.exit(1)

if not validate_availability_zones(availability_zones, aws_region):
    sys.exit(1)

if not validate_environment_consistency(env_type, account):
    sys.exit(1)

if not validate_email(team_email):
    sys.exit(1)

print("✅ Pre-generation validation passed!")