# VPC Advanced - Production-Ready VPC Module

## Overview

This module creates a full-featured, production-ready AWS VPC with all networking components including public/private/database subnets, NAT Gateways, Internet Gateway, VPC Flow Logs, and optional features like VPN Gateway, Transit Gateway attachment, and VPC endpoints.

## Features

- Multi-AZ deployment with configurable number of availability zones
- Public, private, and database subnet tiers
- NAT Gateway (single, per-AZ, or none)
- Internet Gateway for public subnets
- VPC Flow Logs to CloudWatch or S3
- Network ACLs for each subnet tier
- Automatic DNS hostnames and resolution
- IPv6 support (optional)
- VPN Gateway (optional)
- Transit Gateway attachment (optional)
- VPC endpoints for AWS services (optional)
- Default security group management
- Resource tagging strategy
- DHCP options set

## Usage

### Basic VPC

```hcl
module "vpc" {
  source = "../../_library/networking/vpc-advanced"

  name_prefix = "myapp"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_logs = true
  flow_logs_destination_type = "cloud-watch-logs"

  tags = {
    Terraform   = "true"
    Owner       = "platform-team"
  }
}
```

### VPC with VPC Endpoints

```hcl
module "vpc" {
  source = "../../_library/networking/vpc-advanced"

  name_prefix = "myapp"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets    = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # VPC Endpoints
  enable_vpc_endpoints = true
  vpc_endpoints = {
    s3 = {
      service_type = "Gateway"
      route_table_ids = ["private"]
    }
    ec2 = {
      service_type = "Interface"
      subnet_ids = ["private"]
      private_dns_enabled = true
    }
    ecr_api = {
      service_type = "Interface"
      subnet_ids = ["private"]
      private_dns_enabled = true
    }
    ecr_dkr = {
      service_type = "Interface"
      subnet_ids = ["private"]
      private_dns_enabled = true
    }
  }

  tags = {
    Terraform = "true"
  }
}
```

### VPC with Transit Gateway

```hcl
module "vpc" {
  source = "../../_library/networking/vpc-advanced"

  name_prefix = "myapp"
  environment = "production"
  vpc_cidr    = "10.0.0.0/16"

  availability_zones = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets    = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true

  # Transit Gateway
  enable_transit_gateway = true
  transit_gateway_id     = "tgw-1234567890abcdef0"
  transit_gateway_routes = {
    "10.1.0.0/16" = "tgw"
    "10.2.0.0/16" = "tgw"
  }

  tags = {
    Terraform = "true"
  }
}
```

## Examples

See the [examples](./examples/) directory for complete, working examples:

- [complete](./examples/complete/) - Full-featured VPC with all options
- [simple](./examples/simple/) - Basic VPC with public and private subnets

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Name prefix for all resources | `string` | n/a | yes |
| environment | Environment name (e.g., dev, staging, production) | `string` | n/a | yes |
| vpc_cidr | CIDR block for the VPC | `string` | n/a | yes |
| availability_zones | List of availability zones | `list(string)` | n/a | yes |
| public_subnets | List of public subnet CIDR blocks | `list(string)` | `[]` | no |
| private_subnets | List of private subnet CIDR blocks | `list(string)` | `[]` | no |
| database_subnets | List of database subnet CIDR blocks | `list(string)` | `[]` | no |
| enable_nat_gateway | Enable NAT Gateway for private subnets | `bool` | `true` | no |
| single_nat_gateway | Use a single NAT Gateway for all private subnets | `bool` | `false` | no |
| enable_dns_hostnames | Enable DNS hostnames in the VPC | `bool` | `true` | no |
| enable_dns_support | Enable DNS support in the VPC | `bool` | `true` | no |
| enable_ipv6 | Enable IPv6 support | `bool` | `false` | no |
| enable_flow_logs | Enable VPC Flow Logs | `bool` | `true` | no |
| flow_logs_destination_type | Destination type for flow logs (cloud-watch-logs or s3) | `string` | `"cloud-watch-logs"` | no |
| flow_logs_retention_days | Retention period for flow logs in CloudWatch (days) | `number` | `30` | no |
| enable_vpn_gateway | Enable VPN Gateway | `bool` | `false` | no |
| enable_transit_gateway | Enable Transit Gateway attachment | `bool` | `false` | no |
| transit_gateway_id | Transit Gateway ID for attachment | `string` | `null` | no |
| transit_gateway_routes | Map of CIDR blocks to route through Transit Gateway | `map(string)` | `{}` | no |
| enable_vpc_endpoints | Enable VPC endpoints | `bool` | `false` | no |
| vpc_endpoints | Map of VPC endpoint configurations | `map(any)` | `{}` | no |
| default_network_acl_ingress | Default network ACL ingress rules | `list(map(string))` | See defaults | no |
| default_network_acl_egress | Default network ACL egress rules | `list(map(string))` | See defaults | no |
| tags | Additional tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_arn | ARN of the VPC |
| vpc_cidr_block | CIDR block of the VPC |
| vpc_ipv6_cidr_block | IPv6 CIDR block of the VPC |
| public_subnet_ids | List of public subnet IDs |
| private_subnet_ids | List of private subnet IDs |
| database_subnet_ids | List of database subnet IDs |
| public_subnet_cidrs | List of public subnet CIDR blocks |
| private_subnet_cidrs | List of private subnet CIDR blocks |
| database_subnet_cidrs | List of database subnet CIDR blocks |
| public_route_table_ids | List of public route table IDs |
| private_route_table_ids | List of private route table IDs |
| database_route_table_ids | List of database route table IDs |
| internet_gateway_id | ID of the Internet Gateway |
| nat_gateway_ids | List of NAT Gateway IDs |
| nat_gateway_public_ips | List of NAT Gateway public IPs |
| vpn_gateway_id | ID of the VPN Gateway |
| transit_gateway_attachment_id | ID of the Transit Gateway attachment |
| vpc_endpoint_ids | Map of VPC endpoint IDs |
| default_security_group_id | ID of the default security group |
| default_network_acl_id | ID of the default network ACL |
| flow_logs_log_group_name | Name of the flow logs CloudWatch log group |
| flow_logs_iam_role_arn | ARN of the flow logs IAM role |

## Resources

This module creates the following resources:

- `aws_vpc` - VPC
- `aws_subnet` - Public, private, and database subnets
- `aws_internet_gateway` - Internet Gateway
- `aws_eip` - Elastic IPs for NAT Gateways
- `aws_nat_gateway` - NAT Gateways
- `aws_route_table` - Route tables for each subnet tier
- `aws_route_table_association` - Route table associations
- `aws_route` - Routes for Internet Gateway, NAT Gateway, Transit Gateway
- `aws_vpc_ipv6_cidr_block_association` - IPv6 CIDR block (optional)
- `aws_network_acl` - Network ACLs for subnet tiers
- `aws_network_acl_rule` - Network ACL rules
- `aws_flow_log` - VPC Flow Logs
- `aws_cloudwatch_log_group` - CloudWatch log group for flow logs
- `aws_iam_role` - IAM role for flow logs
- `aws_iam_role_policy` - IAM policy for flow logs
- `aws_vpn_gateway` - VPN Gateway (optional)
- `aws_ec2_transit_gateway_vpc_attachment` - Transit Gateway attachment (optional)
- `aws_vpc_endpoint` - VPC endpoints (optional)
- `aws_vpc_dhcp_options` - DHCP options set (optional)

## Known Issues

- NAT Gateway creation can take 2-5 minutes per gateway
- Deleting a VPC with active resources will fail - ensure all resources are removed first
- Flow logs to S3 require the S3 bucket to have the correct bucket policy

## Best Practices

1. **Multi-AZ Deployment**: Always deploy across at least 2 availability zones for high availability
2. **NAT Gateway per AZ**: For production workloads, use one NAT Gateway per AZ to avoid cross-AZ data transfer charges
3. **Subnet Sizing**: Plan CIDR blocks carefully - you cannot change them later without recreating subnets
4. **Flow Logs**: Enable flow logs for security monitoring and troubleshooting
5. **VPC Endpoints**: Use VPC endpoints for S3, ECR, and other AWS services to reduce NAT Gateway costs
6. **Tagging**: Apply consistent tags for cost allocation and resource management

## Changelog

### v1.0.0 (2025-12-02)

- Initial release with full VPC features
- Support for public, private, and database subnets
- NAT Gateway with single or per-AZ options
- VPC Flow Logs to CloudWatch or S3
- VPN Gateway support
- Transit Gateway attachment support
- VPC endpoints support
- IPv6 support
