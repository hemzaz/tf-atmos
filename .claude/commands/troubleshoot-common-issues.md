# Troubleshoot Common Issues

Quick solutions for the most frequent problems encountered during infrastructure development.

## 🔧 System Diagnostics

### Run comprehensive diagnostics
```bash
# Full system health check
make doctor

# Gaia CLI diagnostics
gaia doctor

# Check infrastructure status
make status
```

## ❌ AWS Credential Issues

### Symptoms
- "Unable to locate credentials"
- "Access Denied" errors
- "Invalid security token"

### Solutions
```bash
# Check current AWS identity
aws sts get-caller-identity

# Configure AWS credentials
aws configure

# Check/set AWS profile
export AWS_PROFILE=your-profile-name
echo $AWS_PROFILE

# Verify credentials work
aws s3 ls
```

### Advanced credential troubleshooting
```bash
# Check all configured profiles
aws configure list-profiles

# Check specific profile
aws configure list --profile your-profile

# Use different profile temporarily
AWS_PROFILE=dev-profile make plan
```

## 🐳 Docker Issues

### Docker daemon not running
```bash
# macOS: Start Docker Desktop
open -a Docker

# Linux: Start Docker daemon
sudo systemctl start docker

# Verify Docker is running
docker info
```

### Development environment issues
```bash
# Reset development environment
make dev-reset

# Check container status
docker-compose ps

# View container logs
make dev-logs

# Restart specific service
docker-compose restart backstage
```

### Port conflicts
```bash
# Check what's using port 3000
lsof -i :3000

# Kill process using port
sudo lsof -t -i:3000 | xargs kill -9

# Use different ports (edit docker-compose.yml)
```

## 🏗️ Terraform/Atmos Issues

### State lock issues
```bash
# Check for state locks
aws dynamodb scan --table-name your-lock-table --attributes-to-get LockID State

# Force unlock (BE CAREFUL!)
terraform force-unlock LOCK_ID -force
```

### Invalid configuration
```bash
# Validate and fix formatting
make lint

# Check specific component
make validate

# Plan specific component
make plan-component COMPONENT=vpc
```

### Stack not found errors
```bash
# List available stacks
make list-stacks
gaia list stacks

# Check stack configuration
atmos describe stacks -s orgs/fnx/dev/eu-west-2/testenv-01

# Verify atmos.yaml exists
ls -la atmos.yaml
```

## 📦 Component-Specific Issues

### VPC Issues
```bash
# CIDR block conflicts
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock]'

# Plan VPC changes only
make plan-component COMPONENT=vpc

# Check VPC configuration
atmos terraform plan vpc -s orgs/fnx/dev/eu-west-2/testenv-01
```

### EKS Issues
```bash
# Check EKS cluster status
aws eks describe-cluster --name your-cluster-name

# Verify kubectl access
kubectl cluster-info

# Check EKS add-ons
make plan-component COMPONENT=eks-addons
```

### RDS Issues
```bash
# Check database status
aws rds describe-db-instances

# Test connectivity
# (requires VPN or bastion host for private DBs)
```

## 🔍 Debugging Steps

### 1. Check basics
```bash
# Am I in the right directory?
pwd
ls atmos.yaml

# Do I have the right AWS account?
aws sts get-caller-identity

# Are my tools working?
terraform version
atmos version
```

### 2. Check configurations
```bash
# Validate all configurations
make validate

# Check specific stack exists
atmos list stacks | grep testenv-01

# Verify component configuration
atmos describe component vpc -s orgs/fnx/dev/eu-west-2/testenv-01
```

### 3. Review logs
```bash
# Check recent logs
ls -la logs/

# View specific workflow log
cat logs/workflow-plan-*.log

# Check development logs
make dev-logs
```

### 4. Test connectivity
```bash
# AWS connectivity
aws s3 ls

# Docker connectivity  
docker ps

# Component accessibility
curl -f http://localhost:3000/api/health
```

## 🚨 Emergency Procedures

### Infrastructure stuck in bad state
```bash
# 1. Don't panic - check what's actually broken
make status
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name]'

# 2. Try to plan to see differences
make plan

# 3. Consider targeted fixes
make plan-component COMPONENT=problematic-component

# 4. Last resort: import existing resources
make import-resource
```

### Accidental resource deletion
```bash
# 1. Check Terraform state vs reality
terraform show

# 2. Import resources back into state if they still exist
terraform import aws_instance.example i-1234567890abcdef0

# 3. Or recreate if completely deleted
make apply
```

## 📞 Getting Help

### Self-help resources
```bash
# Show all available commands
make help
gaia --help

# Quick start guide
gaia quick-start

# Read documentation
ls docs/
```

### Log collection for support
```bash
# Collect system info
make doctor > system-info.txt

# Collect recent logs
tar -czf debug-logs.tar.gz logs/

# Collect configuration
tar -czf config-info.tar.gz atmos.yaml components/ stacks/
```

### Information to provide when asking for help
1. Output of `make doctor`
2. Exact error messages
3. Commands that led to the issue
4. Recent changes made
5. Target environment (dev/staging/prod)

## ⚡ Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Command not found | `make install-gaia` or check PATH |
| Permission denied | Check AWS credentials: `aws sts get-caller-identity` |
| Port in use | `make dev-stop` then `make dev-start` |
| State locked | Wait a few minutes, then retry |
| Docker not running | Start Docker Desktop |
| Config validation failed | `make lint` to fix formatting |
| Stack not found | `make list-stacks` to see available |
| Out of disk space | `docker system prune -f` |