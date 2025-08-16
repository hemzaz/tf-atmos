# VPC Example

This example demonstrates how to implement a production-ready VPC with public and private subnets, NAT Gateways, and VPC endpoints using the Atmos framework.

## Architecture

This VPC configuration implements:

- Multiple Availability Zones for high availability
- Public and private subnets
- NAT Gateways in each AZ
- VPC Endpoints for AWS services
- Network ACLs and Security Groups
- Flow Logs for network monitoring
- Transit Gateway attachments (optional)

## Files

- `catalog-vpc.yaml` - Catalog entry for the VPC component
- `dev-vpc.yaml` - Development environment VPC configuration
- `prod-vpc.yaml` - Production environment VPC configuration

## Implementation

### Catalog Configuration

```yaml
# Catalog VPC configuration (catalog/vpc.yaml)
name: vpc
description: "VPC configuration"

components:
  terraform:
    vpc:
      metadata:
        component: vpc
        type: abstract
      vars:
        enabled: true
        region: ${region}
        name: "${tenant}-${environment}-vpc"
        cidr_block: ${vpc_cidr}
        
        # Availability Zones
        availability_zones:
          - "${region}a"
          - "${region}b"
          - "${region}c"
        
        # Subnet configuration
        public_subnets:
          - ${cidrsubnet(vpc_cidr, 4, 0)}
          - ${cidrsubnet(vpc_cidr, 4, 1)}
          - ${cidrsubnet(vpc_cidr, 4, 2)}
        private_subnets:
          - ${cidrsubnet(vpc_cidr, 4, 4)}
          - ${cidrsubnet(vpc_cidr, 4, 5)}
          - ${cidrsubnet(vpc_cidr, 4, 6)}
        database_subnets:
          - ${cidrsubnet(vpc_cidr, 4, 8)}
          - ${cidrsubnet(vpc_cidr, 4, 9)}
          - ${cidrsubnet(vpc_cidr, 4, 10)}
        
        # NAT Gateway configuration
        enable_nat_gateway: true
        single_nat_gateway: false
        one_nat_gateway_per_az: true
        
        # DNS configuration
        enable_dns_hostnames: true
        enable_dns_support: true
        
        # VPC Flow Logs
        enable_flow_log: true
        flow_log_destination_type: "cloud-watch-logs"
        flow_log_log_format: "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"
        flow_log_max_aggregation_interval: 60
        
        # VPC Endpoints
        enable_vpc_endpoints: true
        vpc_endpoint_services:
          - s3
          - dynamodb
          - ssm
          - ssmmessages
          - ec2messages
          - kms
          - logs
        
      # Define common tags
      tags:
        Tenant: ${tenant}
        Account: ${account}
        Environment: ${environment}
        Component: "VPC"
        ManagedBy: "Terraform"
```

### Environment Configuration

```yaml
# Development VPC configuration (account/dev/dev-us-east-1/vpc.yaml)
import:
  - catalog/vpc

vars:
  account: dev
  environment: dev-us-east-1
  region: us-east-1
  tenant: mycompany
  
  # VPC Configuration
  vpc_cidr: "10.0.0.0/16"
  
  # Override catalog settings
  enable_flow_log: false
  single_nat_gateway: true
  
# No dependencies for VPC as it's typically the first component to be deployed

# Additional environment-specific tags
tags:
  Team: "DevOps"
  CostCenter: "Engineering"
  Environment: "Development"
```

## Usage

1. Copy the catalog configuration to `stacks/catalog/vpc.yaml`
2. Copy the environment configuration to `stacks/account/dev/your-environment/vpc.yaml`
3. Customize the configurations as needed
4. Deploy using Atmos:

```bash
# Validate the configuration
atmos terraform validate vpc -s mycompany-dev-dev-us-east-1

# Plan the deployment
atmos terraform plan vpc -s mycompany-dev-dev-us-east-1

# Apply the changes
atmos terraform apply vpc -s mycompany-dev-dev-us-east-1
```

## Best Practices

This example implements these AWS best practices:

1. **High Availability** - Multiple AZs and redundant NAT Gateways
2. **Network Isolation** - Separation of public, private, and database tiers
3. **Security** - Flow logs for network traffic analysis
4. **Performance** - VPC endpoints for optimized AWS service access
5. **Cost Optimization** - Optional single NAT Gateway for development environments

## Customization Options

- **CIDR Ranges**: Adjust the CIDR block and subnet ranges
- **NAT Gateways**: Enable/disable or use single NAT Gateway for cost savings
- **VPC Endpoints**: Add or remove endpoints based on needed AWS services
- **Transit Gateway**: Add Transit Gateway attachment for multi-VPC connectivity
- **Network ACLs**: Add custom network ACLs for additional security layers