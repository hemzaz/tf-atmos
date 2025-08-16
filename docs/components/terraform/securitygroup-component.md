# Security Group Component

_Last Updated: February 28, 2025_

## Overview

This component manages AWS security groups and rules for controlling inbound and outbound network traffic to AWS resources.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Security Group Component                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌─────────────────┐     ┌─────────────────┐    ┌────────┐  │
│  │                 │     │                 │    │        │  │
│  │   Web Tier SG   │────►│   App Tier SG   │───►│  DB SG │  │
│  │                 │     │                 │    │        │  │
│  └─────┬───────────┘     └─────┬───────────┘    └────┬───┘  │
│        │                       │                     │      │
│        ▼                       ▼                     ▼      │
│  ┌─────────────────┐     ┌─────────────────┐    ┌────────┐  │
│  │   Ingress:      │     │   Ingress:      │    │Ingress:│  │
│  │   HTTP/HTTPS    │     │   App port      │    │DB port │  │
│  │   from Internet │     │   from Web SG   │    │from App│  │
│  └─────────────────┘     └─────────────────┘    └────────┘  │
│        │                       │                     │      │
│        ▼                       ▼                     ▼      │
│  ┌─────────────────┐     ┌─────────────────┐    ┌────────┐  │
│  │   Egress:       │     │   Egress:       │    │Egress: │  │
│  │   All Traffic   │     │   All Traffic   │    │All     │  │
│  │                 │     │                 │    │Traffic │  │
│  └─────────────────┘     └─────────────────┘    └────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

The security group component enables you to create and manage multiple AWS security groups with their associated ingress and egress rules. It supports referential security group rules, where one security group can reference another security group as a source or destination.

## Features

- Create and manage multiple security groups
- Define granular inbound and outbound rules
- Support for security group references
- Configurable rule descriptions
- Support for CIDR blocks, prefix lists, and security group sources
- IPv4 and IPv6 support
- Dynamic rule generation
- VPC peering support
- Resource tagging

## Usage

The component is designed to be used with Atmos stacks:

```yaml
components:
  terraform:
    securitygroup/application:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        
        security_groups:
          web:
            description: "Security group for web servers"
            ingress_rules:
              - description: "HTTPS from anywhere"
                from_port: 443
                to_port: 443
                protocol: "tcp"
                cidr_blocks: ["0.0.0.0/0"]
              
              - description: "HTTP from anywhere"
                from_port: 80
                to_port: 80
                protocol: "tcp"
                cidr_blocks: ["0.0.0.0/0"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
          
          app:
            description: "Security group for application servers"
            ingress_rules:
              - description: "App traffic from web tier"
                from_port: 8080
                to_port: 8080
                protocol: "tcp"
                security_groups: ["$${module.security_group.security_group_ids[\"web\"]}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
        
        tags:
          Environment: production
          Project: example
          ManagedBy: atmos
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| vpc_id | VPC ID where security groups will be created | `string` | n/a | yes |
| security_groups | Map of security groups to create with their configuration | `map(any)` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

### Security Group Configuration

Each security group in the `security_groups` map can have the following attributes:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| description | Description of the security group | `string` | Security group for `<n>` |
| ingress_rules | List of ingress rules | `list(map(any))` | `[]` |
| egress_rules | List of egress rules | `list(map(any))` | `[]` |
| tags | Additional tags for this security group | `map(string)` | `{}` |

### Rule Configuration

Each ingress or egress rule can have the following attributes:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| from_port | Start port range | `number` | n/a |
| to_port | End port range | `number` | n/a |
| protocol | Protocol (tcp, udp, icmp, or -1 for all) | `string` | n/a |
| cidr_blocks | List of CIDR blocks to allow | `list(string)` | `null` |
| ipv6_cidr_blocks | List of IPv6 CIDR blocks to allow | `list(string)` | `null` |
| prefix_list_ids | List of prefix list IDs to allow | `list(string)` | `null` |
| security_groups | List of security group IDs to allow | `list(string)` | `null` |
| self | Allow the security group itself as source | `bool` | `null` |
| description | Description of the rule | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| security_group_ids | Map of security group names to their IDs |
| security_group_arns | Map of security group names to their ARNs |
| security_group_vpc_id | VPC ID used for security groups |

## Examples

### Three-Tier Web Application

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/web-app:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        
        # Security Groups
        security_groups:
          web:
            description: "Security group for web servers"
            ingress_rules:
              - description: "HTTPS from anywhere"
                from_port: 443
                to_port: 443
                protocol: "tcp"
                cidr_blocks: ["0.0.0.0/0"]
              
              - description: "HTTP from anywhere"
                from_port: 80
                to_port: 80
                protocol: "tcp"
                cidr_blocks: ["0.0.0.0/0"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
          
          app:
            description: "Security group for application servers"
            ingress_rules:
              - description: "App traffic from web tier"
                from_port: 8080
                to_port: 8080
                protocol: "tcp"
                security_groups: ["$${module.security_group.security_group_ids[\"web\"]}"]
                
              - description: "SSH from bastion"
                from_port: 22
                to_port: 22
                protocol: "tcp"
                security_groups: ["${dep.securitygroup.outputs.bastion_security_group_id}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
          
          db:
            description: "Security group for database servers"
            ingress_rules:
              - description: "PostgreSQL from app tier"
                from_port: 5432
                to_port: 5432
                protocol: "tcp"
                security_groups: ["$${module.security_group.security_group_ids[\"app\"]}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
        
        # Global Tags
        tags:
          Environment: production
          Project: web-application
          ManagedBy: atmos
```

### Container Services Security Groups

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/container-services:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        
        # Security Groups
        security_groups:
          ecs_service:
            description: "Security group for ECS services"
            ingress_rules:
              - description: "HTTPS from ALB"
                from_port: 443
                to_port: 443
                protocol: "tcp"
                security_groups: ["${dep.securitygroup.outputs.alb_security_group_id}"]
              
              - description: "HTTP from ALB"
                from_port: 80
                to_port: 80
                protocol: "tcp"
                security_groups: ["${dep.securitygroup.outputs.alb_security_group_id}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
          
          redis:
            description: "Security group for Redis cache"
            ingress_rules:
              - description: "Redis from ECS services"
                from_port: 6379
                to_port: 6379
                protocol: "tcp"
                security_groups: ["$${module.security_group.security_group_ids[\"ecs_service\"]}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
        
        # Global Tags
        tags:
          Environment: production
          Project: container-services
          ManagedBy: atmos
```

### VPC Endpoint Security Groups

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/vpc-endpoints:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        
        # Security Groups
        security_groups:
          vpc_endpoints:
            description: "Security group for VPC endpoints"
            ingress_rules:
              - description: "HTTPS from VPC CIDR"
                from_port: 443
                to_port: 443
                protocol: "tcp"
                cidr_blocks: ["${dep.vpc.outputs.vpc_cidr_block}"]
            
            egress_rules:
              - description: "Allow all outbound traffic"
                from_port: 0
                to_port: 0
                protocol: "-1"
                cidr_blocks: ["0.0.0.0/0"]
        
        # Global Tags
        tags:
          Environment: production
          Project: vpc-endpoints
          ManagedBy: atmos
```

## Security Best Practices

1. **Principle of Least Privilege**:
   - Only open the ports necessary for your application to function
   - Restrict ingress rules to specific CIDR blocks or security groups
   - Use security groups as sources instead of CIDR blocks for internal traffic

2. **Avoid Overly Permissive Rules**:
   - Don't use `0.0.0.0/0` for ingress rules except for public-facing web services (HTTP/HTTPS)
   - Restrict SSH access to specific IP ranges or VPN/bastion security groups
   - Document the purpose of each rule with descriptive names

3. **Security Group References**:
   - Use security group references instead of CIDR blocks for internal traffic flows
   - This ensures traffic is only allowed from specific resources, not IP ranges that could change

4. **Documentation and Tagging**:
   - Tag all security groups with relevant information
   - Document the purpose of each security group and its rules
   - Use descriptive rule descriptions to aid in auditing

## Troubleshooting

### Common Issues

1. **Rule Changes Not Applied**:
   - Security group rules may take a short time to propagate across AWS regions
   - Check for conflicting rules or configuration errors in the Atmos stack
   - Verify that resource references have been properly resolved

2. **Access Denied**:
   - Check IAM permissions for creating and managing security groups
   - Ensure the IAM role has the necessary permissions: ec2:CreateSecurityGroup, ec2:AuthorizeSecurityGroupIngress, etc.

3. **Rule Limit Exceeded**:
   - AWS has a limit on the number of rules per security group (typically 60 inbound, 60 outbound)
   - Consider using prefix lists for large sets of IPs
   - Consolidate redundant rules where possible

4. **Circular Dependencies**:
   - A common issue is circular references between security groups
   - Restructure your security groups to avoid circular dependencies
   - Consider using a separate Terraform run for different layers of security groups

### Debug Commands

When troubleshooting security group issues, these commands can be helpful:

```bash
# List security groups for a specific VPC
aws ec2 describe-security-groups --filters Name=vpc-id,Values=vpc-12345678

# Check rules for a specific security group
aws ec2 describe-security-groups --group-ids sg-12345678

# Test connectivity between instances
aws ec2 describe-network-insights-analyses --network-insights-analysis-id nia-12345678
```

## Related Resources

- [VPC Component](/components/terraform/vpc/README.md) - Configure VPCs that will contain security groups
- [RDS Component](/components/terraform/rds/README.md) - Database instances that use security groups
- [EC2 Component](/components/terraform/ec2/README.md) - EC2 instances that use security groups
- [ECS Component](/components/terraform/ecs/README.md) - Container services that use security groups

## AWS Documentation

- [AWS Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [Security Group Rules Reference](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules-reference.html)
- [VPC Endpoint Security Group Best Practices](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html)