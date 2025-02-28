# Security Group Component

This component manages AWS security groups and rules for controlling inbound and outbound network traffic.

## Features

- Create and manage multiple security groups
- Define granular inbound and outbound rules
- Support for security group references
- Configurable rule descriptions
- Support for CIDR blocks, prefix lists, and security group sources
- IPv4 and IPv6 support
- Dynamic rule generation
- VPC peering support

## Usage

```hcl
module "security_group" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/securitygroup"
  
  region = var.region
  
  # Security Groups
  security_groups = {
    "web" = {
      name        = "web-sg"
      description = "Security group for web servers"
      vpc_id      = var.vpc_id
      
      ingress_rules = [
        {
          description      = "HTTPS from anywhere"
          from_port        = 443
          to_port          = 443
          protocol         = "tcp"
          cidr_blocks      = ["0.0.0.0/0"]
          ipv6_cidr_blocks = ["::/0"]
        },
        {
          description      = "HTTP from anywhere"
          from_port        = 80
          to_port          = 80
          protocol         = "tcp"
          cidr_blocks      = ["0.0.0.0/0"]
          ipv6_cidr_blocks = ["::/0"]
        }
      ]
      
      egress_rules = [
        {
          description      = "Allow all outbound traffic"
          from_port        = 0
          to_port          = 0
          protocol         = "-1"
          cidr_blocks      = ["0.0.0.0/0"]
          ipv6_cidr_blocks = ["::/0"]
        }
      ]
      
      tags = {
        Name        = "web-sg"
        Environment = "production"
      }
    },
    
    "app" = {
      name        = "app-sg"
      description = "Security group for application servers"
      vpc_id      = var.vpc_id
      
      ingress_rules = [
        {
          description     = "Traffic from web tier"
          from_port       = 8080
          to_port         = 8080
          protocol        = "tcp"
          security_groups = ["${module.security_group.security_group_ids["web"]}"]
        }
      ]
      
      egress_rules = [
        {
          description = "Allow all outbound traffic"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      ]
      
      tags = {
        Name        = "app-sg"
        Environment = "production"
      }
    },
    
    "db" = {
      name        = "db-sg"
      description = "Security group for database servers"
      vpc_id      = var.vpc_id
      
      ingress_rules = [
        {
          description     = "PostgreSQL from app tier"
          from_port       = 5432
          to_port         = 5432
          protocol        = "tcp"
          security_groups = ["${module.security_group.security_group_ids["app"]}"]
        }
      ]
      
      egress_rules = [
        {
          description = "Allow all outbound traffic"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      ]
      
      tags = {
        Name        = "db-sg"
        Environment = "production"
      }
    }
  }
  
  # Global Tags
  tags = {
    Project   = "example"
    ManagedBy = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| security_groups | Map of security group configurations | `map(any)` | `{}` | no |
| default_egress | Default egress rule to add to all security groups | `map(any)` | `{}` | no |
| prefix_list_ids | Map of prefix list IDs for use in security group rules | `map(string)` | `{}` | no |
| create_default_rules | Whether to create default egress rules | `bool` | `true` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| security_group_ids | Map of security group names to their IDs |
| security_group_arns | Map of security group names to their ARNs |
| security_group_names | Map of security group names to their names |
| security_group_vpc_ids | Map of security group names to their VPC IDs |

## Examples

### Three-Tier Web Application

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/web-app:
      vars:
        region: us-west-2
        
        # Security Groups
        security_groups:
          web:
            name: "web-sg"
            description: "Security group for web servers"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
            name: "app-sg"
            description: "Security group for application servers"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
            name: "db-sg"
            description: "Security group for database servers"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
```

### Container Services Security Groups

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/container-services:
      vars:
        region: us-west-2
        
        # Security Groups
        security_groups:
          ecs_service:
            name: "ecs-service-sg"
            description: "Security group for ECS services"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
            name: "redis-sg"
            description: "Security group for Redis cache"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
```

### Security Groups with Prefix Lists

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    securitygroup/vpc-endpoints:
      vars:
        region: us-west-2
        
        # Security Groups
        security_groups:
          vpc_endpoints:
            name: "vpc-endpoints-sg"
            description: "Security group for VPC endpoints"
            vpc_id: ${dep.vpc.outputs.vpc_id}
            
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
        
        # Prefix lists
        prefix_list_ids:
          s3: "pl-123456abcdef"
          dynamodb: "pl-abcdef123456"
        
        # Global Tags
        tags:
          Environment: production
          Project: vpc-endpoints
```

## Implementation Best Practices

1. **Security**:
   - Apply the principle of least privilege: only open necessary ports
   - Use specific CIDR blocks instead of 0.0.0.0/0 when possible
   - For public-facing services, restrict to web ports only (80/443)
   - Use security groups as sources instead of CIDR blocks for internal traffic
   - Document security group rules with descriptive names
   - Use prefix lists for AWS services where appropriate

2. **Organization**:
   - Use a consistent naming convention for security groups
   - Group related security groups together
   - Use tags to identify environment, purpose, and ownership
   - Document the purpose and relationships between security groups

3. **Maintenance**:
   - Regularly audit security group rules
   - Remove unused rules and groups
   - Monitor security group changes
   - Use version control to track changes

4. **Performance and Scalability**:
   - Be aware of AWS limits on security groups and rules
   - Consider using prefix lists for large sets of IPs
   - Use rule descriptions to document the purpose of each rule
   - Reference security groups instead of IP ranges when possible