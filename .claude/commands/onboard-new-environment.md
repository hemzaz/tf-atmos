# Onboard New Environment

Create a complete new environment with all required infrastructure components.

## What this creates
- VPC with public and private subnets
- Security groups with proper configurations
- IAM roles and policies
- Backend state configuration
- Basic monitoring and logging setup

## Before you start
- Decide on environment naming (tenant-environment-account)
- Choose a unique VPC CIDR block that doesn't conflict
- Ensure you have proper AWS permissions
- Plan the environment purpose and requirements

## Commands to run

### Quick onboard with defaults
```bash
# Uses default VPC CIDR 10.0.0.0/16
make onboard
```

### Custom environment onboarding
```bash
# Specify custom CIDR
make onboard-custom VPC_CIDR=10.1.0.0/16

# Using Gaia CLI with full control
gaia workflow onboard-environment \
  --tenant fnx \
  --account staging \
  --environment staging-01 \
  --vpc-cidr 10.2.0.0/16
```

### Interactive onboarding
```bash
# Gaia provides interactive prompts and validation
gaia workflow onboard-environment --tenant mycompany --account dev --environment dev-01
```

## Environment naming conventions

### Standard pattern: `{tenant}-{environment}-{account}`
Examples:
- `fnx-testenv-01-dev` - Development test environment
- `fnx-staging-01-staging` - Staging environment  
- `fnx-production-prod` - Production environment

### Choosing VPC CIDR blocks
- `10.0.0.0/16` - Default for first environment (65,534 IPs)
- `10.1.0.0/16` - Second environment
- `10.2.0.0/16` - Third environment
- Avoid conflicts with existing networks
- Consider future VPC peering requirements

## Onboarding process
1. **Validation** - Checks parameters and prerequisites
2. **Backend setup** - Creates S3 bucket and DynamoDB table for state
3. **VPC creation** - Sets up networking foundation
4. **Security setup** - Creates security groups and IAM roles
5. **Component deployment** - Deploys core infrastructure components
6. **Verification** - Confirms everything is working

## Expected timeline
- Small environment: 10-15 minutes
- Full environment with EKS: 20-30 minutes
- Complex environment: 30-45 minutes

## Verification steps
After onboarding completes:
```bash
# Check the new environment status
gaia status --tenant fnx --account staging --environment staging-01

# Validate all components
make validate TENANT=fnx ACCOUNT=staging ENVIRONMENT=staging-01

# List components in the new environment
gaia list components --stack orgs/fnx/staging/eu-west-2/staging-01
```

## Common issues and solutions

### CIDR conflicts
- Error: "CIDR block overlaps with existing VPC"
- Solution: Choose a different CIDR block
- Check existing VPCs: `aws ec2 describe-vpcs`

### Permission issues
- Error: "Access denied" or "Insufficient permissions"
- Solution: Verify AWS credentials and IAM permissions
- Check: `aws sts get-caller-identity`

### State backend conflicts
- Error: "S3 bucket already exists"
- Solution: Use different environment name or clean up existing resources
- Check existing backends in AWS console

## Post-onboarding tasks
1. **Update documentation** with new environment details
2. **Configure monitoring** and alerting for the environment
3. **Set up CI/CD pipelines** for the new environment
4. **Test deployment** of applications to verify functionality
5. **Update team access** and permissions as needed