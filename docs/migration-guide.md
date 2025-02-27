# Migration Guide for Existing Infrastructure to Atmos

_Last Updated: February 27, 2025_

This guide provides a comprehensive strategy for migrating existing AWS infrastructure into the Atmos framework. It covers assessment, planning, execution, and validation phases to ensure a smooth transition.

## Table of Contents

- [Introduction](#introduction)
- [Assessment Phase](#assessment-phase)
- [Planning Phase](#planning-phase)
- [Migration Execution](#migration-execution)
- [Validation and Testing](#validation-and-testing)
- [Post-Migration Activities](#post-migration-activities)
- [Rollback Procedures](#rollback-procedures)
- [Case Studies](#case-studies)
- [Troubleshooting](#troubleshooting)

## Introduction

Migrating existing infrastructure into Atmos provides numerous benefits:

- **Standardization** - Apply consistent patterns across your infrastructure
- **Scalability** - Easily replicate environments and components
- **Maintainability** - Simplify ongoing maintenance and updates
- **Governance** - Implement organization-wide policies and standards
- **Automation** - Streamline deployments and reduce manual effort

This guide outlines a methodical approach to assess, plan, and execute the migration of existing AWS resources to Atmos-managed infrastructure as code.

## Assessment Phase

### 1. Infrastructure Discovery

Begin by documenting your existing infrastructure:

```bash
# Discover existing resources using AWS CLI
aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0],State.Name,InstanceType]" --output table
aws vpc describe-vpcs --query "Vpcs[].[VpcId,Tags[?Key=='Name'].Value|[0],CidrBlock,IsDefault]" --output table
aws rds describe-db-instances --query "DBInstances[].[DBInstanceIdentifier,Engine,DBInstanceClass,DBInstanceStatus]" --output table
```

Tools for automated discovery:
- [AWS Config](https://aws.amazon.com/config/)
- [CloudMapper](https://github.com/duo-labs/cloudmapper)
- [CloudSploit](https://github.com/aquasecurity/cloudsploit)

### 2. Dependency Mapping

Document resource dependencies in a matrix:

| Resource | Type | Dependencies | Dependent Resources |
|----------|------|--------------|---------------------|
| vpc-12345678 | VPC | None | Subnets, Route Tables, Security Groups |
| subnet-abcdef | Subnet | VPC | EC2 Instances, RDS Instances |
| sg-123456 | Security Group | VPC | EC2 Instances |
| i-abcdef123 | EC2 Instance | VPC, Subnet, Security Group | Load Balancer |

### 3. Resource Categorization

Group resources into functional components:

- **Network Layer** - VPCs, Subnets, Route Tables, Internet Gateways
- **Security Layer** - Security Groups, NACLs, IAM Roles
- **Compute Layer** - EC2 Instances, Auto Scaling Groups
- **Database Layer** - RDS Instances, DynamoDB Tables
- **Service Layer** - Load Balancers, API Gateways, Lambda Functions

### 4. Gap Analysis

Identify differences between existing infrastructure and Atmos best practices:

| Area | Current State | Atmos Best Practice | Gap | Migration Strategy |
|------|--------------|---------------------|-----|-------------------|
| Resource Naming | Inconsistent | `${tenant}-${environment}-resource` | Standardization | Rename during import |
| Tagging | Minimal | Comprehensive tagging strategy | Additional tags | Update after import |
| State Management | Local/Various | S3 + DynamoDB | Centralized backend | Set up backend first |
| IAM Roles | Per-resource | Component-based | Restructure | Create new, migrate permissions |

## Planning Phase

### 1. Migration Strategy Selection

Choose the appropriate migration strategy for each component:

| Strategy | Description | When to Use | Example Components |
|----------|-------------|-------------|-------------------|
| **Lift and Shift** | Import existing resources as-is | Simple resources with few dependencies | S3 Buckets, IAM Roles |
| **Replatform** | Modify configuration during migration | Resources needing standardization | EC2 Instances, Security Groups |
| **Rebuild** | Create new resources and migrate data | Complex resources with major gaps | EKS Clusters, complex networking |
| **Hybrid** | Combination of approaches | Multi-component systems | Application stacks |

### 2. Component Mapping

Map existing resources to Atmos components:

```yaml
# Component Mapping Document
components:
  vpc:
    resources:
      - Resource: vpc-12345678
        Type: aws_vpc
        Import ID: vpc-12345678
      - Resource: subnet-abcdef
        Type: aws_subnet
        Import ID: subnet-abcdef
      - Resource: rtb-123456
        Type: aws_route_table
        Import ID: rtb-123456
        
  securitygroup:
    resources:
      - Resource: sg-123456
        Type: aws_security_group
        Import ID: sg-123456
        
  ec2:
    resources:
      - Resource: i-abcdef123
        Type: aws_instance
        Import ID: i-abcdef123
```

### 3. Migration Sequence Planning

Create a dependency-based migration sequence:

1. **Phase 1**: Backend infrastructure (S3, DynamoDB)
2. **Phase 2**: Network infrastructure (VPC, Subnets, Route Tables)
3. **Phase 3**: Security infrastructure (Security Groups, IAM)
4. **Phase 4**: Database infrastructure (RDS, DynamoDB tables)
5. **Phase 5**: Compute infrastructure (EC2, ECS, EKS)
6. **Phase 6**: Service infrastructure (Load Balancers, API Gateway)
7. **Phase 7**: Application infrastructure (Lambda, ECS Services)

### 4. Stack Configuration Design

Design stack configurations aligned with your organization:

```yaml
# Example stack structure
stacks:
  catalog:
    - vpc.yaml
    - securitygroup.yaml
    - ec2.yaml
    - rds.yaml
    
  account:
    dev:
      us-east-1:
        - vpc.yaml
        - securitygroup.yaml
        - ec2.yaml
        - rds.yaml
```

## Migration Execution

### 1. Terraform State Setup

Set up the Atmos backend infrastructure first:

```bash
# Bootstrap the backend infrastructure
atmos workflow bootstrap-backend tenant=mycompany region=us-east-1
```

### 2. Creating Component Files

Create component files based on the template structure:

```bash
# Create component directories
mkdir -p components/terraform/vpc
mkdir -p components/terraform/securitygroup
mkdir -p components/terraform/ec2
mkdir -p components/terraform/rds

# Copy template files
cp templates/terraform-component/* components/terraform/vpc/
cp templates/terraform-component/* components/terraform/securitygroup/
# ... repeat for other components
```

### 3. Resource Import Process

#### Prepare Import Script

```bash
#!/bin/bash
# import-resources.sh

# Import VPC resources
atmos terraform import vpc.aws_vpc.main vpc-12345678 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.public[0] subnet-public1 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.public[1] subnet-public2 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.private[0] subnet-private1 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.private[1] subnet-private2 -s mycompany-dev-us-east-1

# Import security group resources
atmos terraform import securitygroup.aws_security_group.main sg-123456 -s mycompany-dev-us-east-1

# Import EC2 resources
atmos terraform import ec2.aws_instance.app i-abcdef123 -s mycompany-dev-us-east-1

# Import RDS resources
atmos terraform import rds.aws_db_instance.database db-abcdef -s mycompany-dev-us-east-1
```

#### Execute Import

```bash
# Run the import script
chmod +x import-resources.sh
./import-resources.sh
```

#### Using Atmos Import Workflow

```bash
# Configure import workflow
cat > workflows/import-vpc.yaml << EOF
name: import-vpc
description: "Import VPC resources into Terraform state"
args:
  - name: tenant
    required: true
  - name: account
    required: true
  - name: environment
    required: true
steps:
  - command: atmos
    args:
      - terraform
      - import
      - vpc.aws_vpc.main
      - vpc-12345678
      - -s
      - "{tenant}-{account}-{environment}"
  # ... additional import steps ...
EOF

# Execute import workflow
atmos workflow import-vpc tenant=mycompany account=dev environment=us-east-1
```

### 4. State Verification

After import, verify the state:

```bash
# List resources in state
atmos terraform state list vpc -s mycompany-dev-us-east-1

# Show specific resource details
atmos terraform state show vpc.aws_vpc.main -s mycompany-dev-us-east-1
```

### 5. Terraform Plan and Apply

Resolve any configuration drift:

```bash
# Check for configuration drift
atmos terraform plan vpc -s mycompany-dev-us-east-1

# Apply changes if needed
atmos terraform apply vpc -s mycompany-dev-us-east-1
```

## Validation and Testing

### 1. Drift Detection

```bash
# Run drift detection workflow
atmos workflow drift-detection tenant=mycompany account=dev environment=us-east-1
```

### 2. Functional Testing

Verify that imported infrastructure functions correctly:

```bash
# Test connectivity to EC2 instances
ping $(atmos terraform output ec2.instance_public_ip -s mycompany-dev-us-east-1)

# Test RDS connectivity
mysql -h $(atmos terraform output rds.endpoint -s mycompany-dev-us-east-1) -u admin -p
```

### 3. Infrastructure Validation

```bash
# Validate changes through the AWS console or CLI
aws ec2 describe-instances --instance-ids i-abcdef123
aws rds describe-db-instances --db-instance-identifier db-abcdef
```

## Post-Migration Activities

### 1. Documentation Update

Update documentation to reflect the migrated infrastructure:

- Component usage documentation
- Architecture diagrams
- Runbooks and operational procedures

### 2. Knowledge Transfer

Conduct sessions for team members on:

- Atmos concepts and usage
- New deployment processes
- Troubleshooting procedures

### 3. Cleanup

Remove obsolete resources and configurations:

```bash
# Clean up legacy configuration files
rm -rf legacy-terraform/

# Remove old CI/CD configurations
rm .github/workflows/legacy-deploy.yml
```

## Rollback Procedures

In case of migration issues, prepare rollback procedures:

### 1. State Rollback

```bash
# Backup the current state before rollback
aws s3 cp s3://mycompany-terraform-state/dev/us-east-1/vpc/terraform.tfstate \
  s3://mycompany-terraform-state/dev/us-east-1/vpc/terraform.tfstate.bak

# Restore previous state
aws s3 cp s3://mycompany-terraform-state-backup/dev/us-east-1/vpc/terraform.tfstate \
  s3://mycompany-terraform-state/dev/us-east-1/vpc/terraform.tfstate
```

### 2. Resource Recovery

For resources modified during migration:

```bash
# Restore EC2 instance from snapshot
aws ec2 create-volume --snapshot-id snap-12345678 --availability-zone us-east-1a
aws ec2 attach-volume --volume-id vol-12345678 --instance-id i-abcdef123 --device /dev/sdf

# Restore RDS instance from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier db-abcdef \
  --db-snapshot-identifier rds:db-abcdef-2023-01-01-00-00
```

## Case Studies

### Example 1: VPC Migration

**Scenario**: Migrating a legacy VPC with multiple subnets and complex routing.

**Approach**:
1. Document the existing VPC configuration
2. Create the corresponding Atmos component
3. Import VPC and associated resources
4. Resolve any configuration drift
5. Validate functionality

**Terraform Configuration**:

```hcl
# components/terraform/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  
  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-public-${count.index + 1}"
      Tier = "Public"
    }
  )
}

# ... more resources ...
```

**Import Commands**:

```bash
atmos terraform import vpc.aws_vpc.main vpc-12345678 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.public[0] subnet-public1 -s mycompany-dev-us-east-1
atmos terraform import vpc.aws_subnet.public[1] subnet-public2 -s mycompany-dev-us-east-1
```

### Example 2: RDS Migration

**Scenario**: Migrating a production RDS instance without downtime.

**Approach**:
1. Create a read replica of the existing RDS instance
2. Import the read replica into Terraform
3. Promote the read replica to primary
4. Update DNS to point to the new instance
5. Decommission the old instance

**Terraform Configuration**:

```hcl
# components/terraform/rds/main.tf
resource "aws_db_instance" "database" {
  allocated_storage    = var.allocated_storage
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  db_name              = var.db_name
  username             = var.username
  password             = var.password
  parameter_group_name = var.parameter_group_name
  
  # ... more configuration ...
  
  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-database"
    }
  )
}
```

## Troubleshooting

### Common Migration Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| **Import fails with resource not found** | Resource ID incorrect or resource deleted | Verify resource exists with AWS CLI/Console |
| **Configuration drift after import** | Terraform config doesn't match actual resources | Update Terraform configuration to match or apply changes |
| **Dependency errors** | Resources imported in incorrect order | Import dependent resources first or use `-allow-missing-config` |
| **State lock errors** | DynamoDB lock table issues | Check lock table entries and remove stale locks |
| **Authentication failures** | IAM permissions incorrect | Verify AWS credentials and IAM permissions |

### Resource-Specific Troubleshooting

#### VPC Issues

```bash
# Check VPC configuration
aws ec2 describe-vpcs --vpc-id vpc-12345678

# Check subnet configuration
aws ec2 describe-subnets --filter "Name=vpc-id,Values=vpc-12345678"

# Check route tables
aws ec2 describe-route-tables --filter "Name=vpc-id,Values=vpc-12345678"
```

#### Security Group Issues

```bash
# Check security group rules
aws ec2 describe-security-groups --group-id sg-123456

# Check security group references
aws ec2 describe-network-interfaces --filter "Name=group-id,Values=sg-123456"
```

---

This guide provides a comprehensive framework for migrating existing infrastructure to Atmos. Every migration is unique, and the approach should be tailored to your specific environment, requirements, and constraints.