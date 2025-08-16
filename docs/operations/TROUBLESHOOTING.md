# Troubleshooting Guide

Common issues and solutions for the Terraform/Atmos infrastructure project.

## Quick Diagnosis

### 1. Health Check Commands

Run these commands to quickly diagnose issues:

```bash
# Check tool versions
terraform version    # Should be 1.11.0+
atmos version       # Should be 1.163.0+
python3 --version   # Should be 3.11+
aws --version       # Should be 2.0+

# Validate configuration
atmos validate stacks
atmos workflow validate

# Test connectivity  
aws sts get-caller-identity
```

### 2. Common Error Patterns

| Error Message | Section | Fix |
|--------------|---------|-----|
| "No such file or directory: atmos" | [Installation Issues](#installation-issues) | Install Atmos CLI |
| "Error: component 'vpc' not found" | [Component Resolution](#component-resolution-errors) | Check stack configuration |
| "AccessDenied" or "InvalidAccessKeyId" | [AWS Authentication](#aws-authentication-problems) | Configure AWS credentials |
| "No module named 'typer'" | [Python Dependencies](#python-environment-issues) | Install Python dependencies |
| "DynamoDB lock timeout" | [State Management](#terraform-state-issues) | Clear abandoned locks |
| "Error: unsupported shell: zsh" | [Shell Compatibility](#shell-compatibility-issues) | Use bash or configure shell |

## Installation Issues

### Problem: Atmos CLI not found

```bash
$ atmos version
bash: atmos: command not found
```

**Solution:**

```bash
# macOS (Homebrew)
brew install atmos

# Linux
curl -sSL https://get.atmos.tools/install.sh | bash

# Windows
# Download from: https://github.com/cloudposse/atmos/releases
# Add to PATH

# Verify installation
atmos version
```

### Problem: Terraform version mismatch

```bash
$ terraform version
Terraform v1.9.0  # Wrong version
```

**Solution:**

```bash
# macOS - Use specific version
brew uninstall terraform
brew install terraform@1.11

# Linux - Download specific version
wget https://releases.hashicorp.com/terraform/1.11.0/terraform_1.11.0_linux_amd64.zip
unzip terraform_1.11.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify
terraform version  # Should show 1.11.0
```

### Problem: Python dependencies missing

```bash
$ gaia --help
ModuleNotFoundError: No module named 'typer'
```

**Solution:**

```bash
# Install Gaia CLI
cd tf-atmos
pip install -e ./gaia

# Or use virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate
pip install -e ./gaia

# Verify
gaia --help
```

## Component Resolution Errors

### Problem: Component not found

```bash
$ atmos terraform plan vpc -s fnx-dev-testenv-01
Error: component 'vpc' not found in stack 'fnx-dev-testenv-01'
```

**Solution:**

```bash
# 1. Verify stack exists
atmos describe stacks | grep fnx-dev-testenv-01

# 2. Use user-friendly stack listing
./scripts/list_stacks.sh

# 3. Check component configuration
ls components/terraform/vpc/

# 4. Validate stack configuration
atmos describe config -s fnx-dev-testenv-01

# 5. If still not working, try the full stack path:
atmos terraform plan vpc -s stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml
```

### Problem: Invalid stack format

```bash
Error: invalid stack format
```

**Solution:**

Check `atmos.yaml` configuration:

```bash
# Verify atmos.yaml exists and is valid
cat atmos.yaml | grep -A5 "stacks:"

# The working configuration should be:
# stacks:
#   name_pattern: "{dir}"
#   included_paths:
#     - "orgs/**/**/**/*.yaml"
```

### Problem: Component validation fails

```bash
$ atmos workflow validate
Error: component validation failed
```

**Solution:**

```bash
# Validate individual components
for component in vpc eks rds; do
  echo "Validating $component..."
  atmos terraform validate $component -s fnx-dev-testenv-01 || echo "FAILED: $component"
done

# Check terraform syntax
terraform fmt -check -recursive components/terraform/

# Validate specific component directory
cd components/terraform/vpc
terraform init
terraform validate
```

## AWS Authentication Problems

### Problem: AWS credentials not found

```bash
$ aws sts get-caller-identity
Unable to locate credentials
```

**Solution:**

```bash
# Option 1: Configure AWS CLI
aws configure

# Option 2: Set environment variables  
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"

# Option 3: Use AWS profiles
aws configure --profile dev
export AWS_PROFILE=dev

# Verify
aws sts get-caller-identity
```

### Problem: Permission denied errors

```bash
Error: AccessDenied: User is not authorized to perform: iam:CreateRole
```

**Solution:**

Check required AWS permissions:

```bash
# Verify your identity
aws sts get-caller-identity

# Check if you can assume the correct role
aws sts assume-role --role-arn "arn:aws:iam::ACCOUNT:role/AdminRole" --role-session-name "test"

# Required permissions for this project:
# - ec2:*
# - eks:*  
# - rds:*
# - iam:*
# - s3:*
# - dynamodb:*
# - secretsmanager:*
```

### Problem: Cross-account access issues

```bash
Error: operation error STS: AssumeRole, https response error StatusCode: 403
```

**Solution:**

```bash
# 1. Verify account IDs in .env
cat .env | grep AWS_ACCOUNT_ID

# 2. Check trust relationships in target account
aws iam get-role --role-name AtmosExecutionRole

# 3. Verify external ID if required
# Edit .env and add:
# AWS_EXTERNAL_ID=your-external-id
```

## Terraform State Issues

### Problem: DynamoDB lock timeout

```bash
Error: Error acquiring the state lock: ConditionalCheckFailedException
```

**Solution:**

```bash
# 1. List active locks
aws dynamodb scan \
  --table-name atmos-terraform-state-lock \
  --attributes-to-get LockID State

# 2. Force unlock (use with caution!)
terraform force-unlock LOCK_ID

# 3. Clear abandoned locks
aws dynamodb delete-item \
  --table-name atmos-terraform-state-lock \
  --key '{"LockID":{"S":"LOCK_ID"}}'

# 4. For persistent issues, check if another process is running
ps aux | grep terraform
```

### Problem: State file corruption

```bash
Error: state file appears to be corrupted
```

**Solution:**

```bash
# 1. Backup current state
aws s3 cp s3://atmos-terraform-state-fnx-dev-testenv-01/terraform/fnx/testenv-01/vpc.tfstate ./vpc.tfstate.backup

# 2. Try to recover
terraform state list -state=./vpc.tfstate.backup

# 3. If corrupted, restore from backup
aws s3 ls s3://atmos-terraform-state-fnx-dev-testenv-01/terraform/fnx/testenv-01/ --recursive

# 4. Replace with previous version
aws s3 cp s3://bucket/path/to/previous/vpc.tfstate s3://bucket/path/to/current/vpc.tfstate
```

## Python Environment Issues

### Problem: Virtual environment activation fails

```bash
$ source .venv/bin/activate
bash: .venv/bin/activate: No such file or directory
```

**Solution:**

```bash
# Create virtual environment
python3 -m venv .venv

# Activate (Linux/macOS)
source .venv/bin/activate

# Activate (Windows)
.venv\Scripts\activate

# Install dependencies
pip install -e ./gaia

# Verify
which python  # Should point to .venv
```

### Problem: Package import errors

```bash
ImportError: cannot import name 'typer' from 'gaia'
```

**Solution:**

```bash
# Clean installation
pip uninstall -y $(pip freeze)
pip install -e ./gaia

# Or reinstall specific package
pip install --force-reinstall typer

# Check installed packages
pip list | grep -E "(typer|click|pydantic)"
```

## Shell Compatibility Issues

### Problem: Shell script compatibility errors

```bash
Error: unsupported shell: zsh
./scripts/list_stacks.sh: line 15: syntax error
```

**Solution:**

```bash
# Use bash explicitly
bash ./scripts/list_stacks.sh

# Or change default shell temporarily
chsh -s /bin/bash

# For persistent zsh users, add to ~/.zshrc:
echo 'alias atmos-scripts="bash"' >> ~/.zshrc
source ~/.zshrc
```

### Problem: Path resolution issues

```bash
./scripts/list_stacks.sh: No such file or directory
```

**Solution:**

```bash
# Always run from project root
cd /path/to/tf-atmos

# Make scripts executable
chmod +x scripts/*.sh

# Use absolute paths
bash $PWD/scripts/list_stacks.sh
```

## Workflow Execution Problems

### Problem: Workflow hangs or times out

```bash
$ atmos workflow apply-environment tenant=fnx account=dev environment=testenv-01
# Hangs indefinitely
```

**Solution:**

```bash
# 1. Check for resource locks
aws dynamodb scan --table-name atmos-terraform-state-lock

# 2. Monitor in separate terminal
tail -f /var/log/atmos.log

# 3. Run with verbose output
ATMOS_LOG_LEVEL=DEBUG atmos workflow apply-environment tenant=fnx account=dev environment=testenv-01

# 4. Break down into individual components
atmos terraform plan vpc -s fnx-dev-testenv-01
atmos terraform plan eks -s fnx-dev-testenv-01
```

### Problem: Workflow dependency errors

```bash
Error: dependency cycle detected
```

**Solution:**

```bash
# 1. Check component dependencies
grep -r "depends_on" components/terraform/

# 2. Validate dependency graph
atmos describe component vpc -s fnx-dev-testenv-01

# 3. Apply dependencies in order
atmos terraform apply vpc -s fnx-dev-testenv-01
atmos terraform apply eks -s fnx-dev-testenv-01
atmos terraform apply eks-addons -s fnx-dev-testenv-01
```

## Configuration Issues

### Problem: Environment variables not loaded

```bash
Error: REQUIRED_ACCOUNT_ID must be set
```

**Solution:**

```bash
# 1. Verify .env file exists and has correct values
cat .env | grep AWS_ACCOUNT_ID

# 2. Load environment variables
source .env

# 3. Export specific variables
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-west-2"

# 4. Verify variables are set
echo $AWS_ACCOUNT_ID
```

### Problem: YAML configuration errors

```bash
Error: yaml: unmarshal errors
```

**Solution:**

```bash
# 1. Validate YAML syntax
yamllint stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml

# 2. Check for common YAML errors
# - Incorrect indentation (use 2 spaces, not tabs)
# - Missing quotes around strings with special characters
# - Inconsistent data types

# 3. Use a YAML validator online or:
python3 -c "import yaml; yaml.safe_load(open('file.yaml'))"
```

## Performance Issues

### Problem: Slow component discovery

```bash
$ atmos describe stacks
# Takes 30+ seconds
```

**Solution:**

```bash
# 1. Clear Atmos cache
rm -rf ~/.atmos/cache

# 2. Use specific stack patterns
atmos describe stacks --include-pattern="fnx-dev-*"

# 3. Enable caching in atmos.yaml:
# settings:
#   cache:
#     enabled: true
#     ttl: 3600
```

### Problem: Large terraform plans

```bash
Plan: 500+ to add, 0 to change, 0 to destroy
# Plan file too large
```

**Solution:**

```bash
# 1. Plan individual components
atmos terraform plan vpc -s fnx-dev-testenv-01
atmos terraform plan eks -s fnx-dev-testenv-01

# 2. Use targeted applies
terraform apply -target=module.vpc

# 3. Break down large components into smaller ones
```

## Debugging Commands

### Comprehensive Health Check

```bash
#!/bin/bash
# Save as scripts/health-check.sh

echo "=== Tool Versions ==="
terraform version
atmos version  
python3 --version
aws --version

echo -e "\n=== Environment Variables ==="
echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
echo "AWS_REGION: $AWS_REGION" 
echo "AWS_PROFILE: $AWS_PROFILE"

echo -e "\n=== AWS Authentication ==="
aws sts get-caller-identity || echo "AWS auth failed"

echo -e "\n=== Atmos Configuration ==="
atmos validate stacks || echo "Stack validation failed"

echo -e "\n=== Available Stacks ==="
./scripts/list_stacks.sh || echo "Stack listing failed"

echo -e "\n=== Test Component ==="
atmos terraform plan vpc -s fnx-dev-testenv-01 --dry-run || echo "Component test failed"

echo -e "\n=== Python Environment ==="
python3 -c "import typer; print('Typer OK')" || echo "Python deps missing"
gaia --help >/dev/null && echo "Gaia CLI OK" || echo "Gaia CLI failed"
```

### Debug Environment

```bash
# Enable verbose logging
export ATMOS_LOG_LEVEL=DEBUG
export TF_LOG=DEBUG

# Run command with full debugging
atmos terraform plan vpc -s fnx-dev-testenv-01 2>&1 | tee debug.log

# Analyze logs
grep -i error debug.log
grep -i warning debug.log
```

## Getting More Help

### 1. Collect Debug Information

Before asking for help, collect this information:

```bash
# System information
uname -a
terraform version
atmos version
python3 --version
aws --version

# Error logs  
atmos terraform plan vpc -s fnx-dev-testenv-01 2>&1 | tee error.log

# Configuration
cat atmos.yaml
ls -la components/terraform/
ls -la stacks/orgs/fnx/dev/eu-west-2/
```

### 2. Common Support Resources

- **Working Stack**: `fnx-dev-testenv-01` is validated and working
- **Examples**: See `/examples` directory for working configurations
- **Component Docs**: Each component has a README.md with usage examples
- **Scripts**: Use `./scripts/list_stacks.sh` for user-friendly stack listing

### 3. Escalation Path

1. **Self-Service**: Use this troubleshooting guide
2. **Examples**: Check `/examples` for similar configurations  
3. **Documentation**: Review component READMEs and `/docs`
4. **Debug**: Run health check script and collect logs
5. **Ask for Help**: Provide debug information from step 1

---

**Last Updated**: Based on resolved stack issues and working `fnx-dev-testenv-01` configuration.