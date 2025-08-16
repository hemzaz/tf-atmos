# VPC Component

_Last Updated: February 27, 2025_

A comprehensive AWS VPC infrastructure module for Atmos that creates all networking resources needed for a multi-AZ, production-ready Virtual Private Cloud.

## Overview

This component creates a complete VPC infrastructure including:

- VPC with configurable CIDR block
- Public and private subnets across multiple Availability Zones
- Internet Gateway for public subnets
- NAT Gateways for private subnet internet access
- Route Tables for traffic management
- VPC Endpoints for AWS service access
- Network ACLs for additional security
- Flow Logs for network traffic analysis
- Transit Gateway attachments (optional)
- VPN Gateway for on-premises connectivity (optional)

## Usage

### Basic Usage

```yaml
# catalog/vpc.yaml
name: vpc
description: "VPC configuration"

components:
  terraform:
    vpc:
      metadata:
        component: vpc
      vars:
        region: ${region}
        name: "${tenant}-${environment}-vpc"
        vpc_cidr: "10.0.0.0/16"
        azs: 
          - "${region}a"
          - "${region}b"
          - "${region}c"
        public_subnets:
          - "10.0.1.0/24"
          - "10.0.2.0/24"
          - "10.0.3.0/24"
        private_subnets:
          - "10.0.11.0/24"
          - "10.0.12.0/24"
          - "10.0.13.0/24"
        database_subnets:
          - "10.0.21.0/24"
          - "10.0.22.0/24"
          - "10.0.23.0/24"
        enable_nat_gateway: true
        single_nat_gateway: false
        one_nat_gateway_per_az: true
        enable_vpn_gateway: false
        enable_flow_log: true
        create_database_subnet_group: true
```

### Environment-specific configuration

```yaml
# account/dev/us-east-1/vpc.yaml
import:
  - catalog/vpc

vars:
  account: dev
  environment: us-east-1
  region: us-east-1
  tenant: mycompany
  
  # Override catalog settings for dev
  vpc_cidr: "10.1.0.0/16"
  single_nat_gateway: true  # Use single NAT gateway for cost savings in dev
  
  # Enable VPC endpoints
  enable_endpoints: true
  endpoint_services:
    - s3
    - dynamodb

tags:
  Environment: "Development"
  Team: "Platform"
  CostCenter: "Platform-1234"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `region` | AWS region | `string` | - | Yes |
| `assume_role_arn` | ARN of the IAM role to assume | `string` | `null` | No |
| `enabled` | Set to false to prevent resource creation | `bool` | `true` | No |
| `name` | Name for this VPC | `string` | - | Yes |
| `vpc_cidr` | CIDR block for the VPC | `string` | - | Yes |
| `azs` | List of Availability Zones | `list(string)` | - | Yes |
| `public_subnets` | List of public subnet CIDR blocks | `list(string)` | `[]` | No |
| `private_subnets` | List of private subnet CIDR blocks | `list(string)` | `[]` | No |
| `database_subnets` | List of database subnet CIDR blocks | `list(string)` | `[]` | No |
| `enable_dns_hostnames` | Enable DNS hostnames in the VPC | `bool` | `true` | No |
| `enable_dns_support` | Enable DNS support in the VPC | `bool` | `true` | No |
| `enable_nat_gateway` | Enable NAT Gateways for private subnets | `bool` | `true` | No |
| `single_nat_gateway` | Use a single NAT Gateway for all private subnets | `bool` | `false` | No |
| `one_nat_gateway_per_az` | Create one NAT Gateway per AZ | `bool` | `true` | No |
| `enable_vpn_gateway` | Enable VPN Gateway | `bool` | `false` | No |
| `enable_flow_log` | Enable VPC Flow Logs | `bool` | `true` | No |
| `flow_log_destination_type` | Type of flow log destination | `string` | `"cloud-watch-logs"` | No |
| `create_database_subnet_group` | Create database subnet group | `bool` | `true` | No |
| `enable_endpoints` | Enable VPC endpoints | `bool` | `false` | No |
| `endpoint_services` | List of VPC endpoint services to create | `list(string)` | `[]` | No |
| `tags` | Additional tags for all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `vpc_default_security_group_id` | Default security group ID |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `database_subnet_ids` | List of database subnet IDs |
| `public_route_table_ids` | List of public route table IDs |
| `private_route_table_ids` | List of private route table IDs |
| `database_route_table_ids` | List of database route table IDs |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `igw_id` | Internet Gateway ID |
| `vpn_gateway_id` | VPN Gateway ID |
| `vpc_endpoint_ids` | Map of VPC endpoint IDs |
| `database_subnet_group_id` | Database subnet group ID |
| `database_subnet_group_name` | Database subnet group name |

## Features

### Multi-AZ Support

The VPC component creates resources across multiple Availability Zones for high availability:

```yaml
azs:
  - "us-east-1a"
  - "us-east-1b"
  - "us-east-1c"
```

### NAT Gateway Options

Configure NAT Gateways based on requirements:

```yaml
# High-availability production setup
enable_nat_gateway: true
single_nat_gateway: false
one_nat_gateway_per_az: true

# Cost-optimized development setup
enable_nat_gateway: true
single_nat_gateway: true
one_nat_gateway_per_az: false
```

### VPC Endpoints

Enable VPC endpoints for direct AWS service access:

```yaml
enable_endpoints: true
endpoint_services:
  - s3
  - dynamodb
  - ssm
  - ssmmessages
  - ec2messages
  - kms
  - logs
```

### Flow Logs

Configure VPC Flow Logs for network monitoring:

```yaml
enable_flow_log: true
flow_log_destination_type: "cloud-watch-logs"
flow_log_retention_in_days: 14
```

### Transit Gateway Integration

Connect to a Transit Gateway for multi-VPC networking:

```yaml
enable_transit_gateway_attachment: true
transit_gateway_id: "tgw-1234567890abcdef0"
```

## Architecture

This diagram shows the architecture created by this component:

```
                                  +------------------+
                                  |     Internet     |
                                  +--------+---------+
                                           |
                                  +--------+---------+
                                  | Internet Gateway |
                                  +--------+---------+
                                           |
       +------------------------------------------------------------------+
       |                              VPC CIDR                             |
       |                                                                   |
       |  +----------------+    +----------------+    +----------------+   |
       |  |  Public Subnet |    |  Public Subnet |    |  Public Subnet |   |
       |  |    AZ1         |    |    AZ2         |    |    AZ3         |   |
       |  +--------+-------+    +--------+-------+    +--------+-------+   |
       |           |                     |                     |           |
       |  +--------+-------+    +--------+-------+    +--------+-------+   |
       |  |   NAT Gateway  |    |   NAT Gateway  |    |   NAT Gateway  |   |
       |  +--------+-------+    +--------+-------+    +--------+-------+   |
       |           |                     |                     |           |
       |  +--------+-------+    +--------+-------+    +--------+-------+   |
       |  | Private Subnet |    | Private Subnet |    | Private Subnet |   |
       |  |    AZ1         |    |    AZ2         |    |    AZ3         |   |
       |  +----------------+    +----------------+    +----------------+   |
       |                                                                   |
       |  +----------------+    +----------------+    +----------------+   |
       |  | Database Subnet|    | Database Subnet|    | Database Subnet|   |
       |  |    AZ1         |    |    AZ2         |    |    AZ3         |   |
       |  +----------------+    +----------------+    +----------------+   |
       |                                                                   |
       |  +----------------+                                               |
       |  | VPC Endpoints  |                                               |
       |  | (S3, DynamoDB, |                                               |
       |  |  etc.)         |                                               |
       |  +----------------+                                               |
       +------------------------------------------------------------------+
```

## Best Practices

- Use the standard CIDR range for each environment with a unique second octet
- Enable multiple NAT Gateways for production environments
- Use a single NAT Gateway for development/testing to reduce costs
- Always enable VPC Flow Logs for security and troubleshooting
- Use VPC Endpoints to keep traffic within the AWS network
- Use consistent subnet sizing to ensure scalability

## Examples

### Basic Development VPC

```yaml
vars:
  vpc_cidr: "10.1.0.0/16"
  azs:
    - "us-east-1a"
    - "us-east-1b"
  public_subnets:
    - "10.1.1.0/24"
    - "10.1.2.0/24"
  private_subnets:
    - "10.1.11.0/24"
    - "10.1.12.0/24"
  database_subnets:
    - "10.1.21.0/24"
    - "10.1.22.0/24"
  enable_nat_gateway: true
  single_nat_gateway: true
  enable_vpn_gateway: false
```

### Production-Ready VPC

```yaml
vars:
  vpc_cidr: "10.0.0.0/16"
  azs:
    - "us-east-1a"
    - "us-east-1b"
    - "us-east-1c"
  public_subnets:
    - "10.0.1.0/24"
    - "10.0.2.0/24"
    - "10.0.3.0/24"
  private_subnets:
    - "10.0.11.0/24"
    - "10.0.12.0/24"
    - "10.0.13.0/24"
  database_subnets:
    - "10.0.21.0/24"
    - "10.0.22.0/24"
    - "10.0.23.0/24"
  enable_nat_gateway: true
  single_nat_gateway: false
  one_nat_gateway_per_az: true
  enable_vpn_gateway: true
  enable_flow_log: true
  flow_log_retention_in_days: 30
  enable_endpoints: true
  endpoint_services:
    - s3
    - dynamodb
    - ssm
    - kms
```

## Related Components

- **backend** - For setting up Terraform state management
- **securitygroup** - For creating Security Groups
- **iam** - For creating IAM roles and policies
- **ec2** - For deploying EC2 instances in the VPC
- **rds** - For creating RDS databases in database subnets

## Troubleshooting

### Common Issues

1. **CIDR Block Conflicts**: Ensure VPC CIDR blocks don't overlap between environments
   
   ```bash
   # Check existing VPCs
   aws ec2 describe-vpcs --query "Vpcs[].CidrBlock"
   ```

2. **NAT Gateway Creation Failure**: Ensure you have available Elastic IP addresses
   
   ```bash
   # Check EIP quota
   aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3
   ```

3. **VPC Endpoint Service Not Available**: Verify the endpoint service is available in your region
   
   ```bash
   # List available endpoint services
   aws ec2 describe-vpc-endpoint-services
   ```

### Validation Commands

```bash
# Validate VPC configuration
atmos terraform validate vpc -s mycompany-dev-us-east-1

# View Terraform plan
atmos terraform plan vpc -s mycompany-dev-us-east-1

# Check component outputs after deployment
atmos terraform output vpc -s mycompany-dev-us-east-1
```