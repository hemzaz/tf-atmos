# EC2 Component

_Last Updated: February 28, 2025_

## Overview

A versatile AWS EC2 infrastructure component for Atmos that manages EC2 instances, security groups, IAM roles, and related resources for your cloud workloads.

This component provides a flexible way to deploy and manage AWS EC2 resources including:

- EC2 instances with customizable configurations
- Security groups with configurable rules
- IAM roles and instance profiles with proper permissions
- EBS volumes with customizable sizes and types
- System Manager integration for secure instance management
- Detailed resource tagging and naming conventions

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       AWS VPC                           │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │                   Subnet                          │  │
│  │                                                   │  │
│  │  ┌───────────────┐       ┌───────────────────┐    │  │
│  │  │  EC2 Instance │       │ Security Group    │    │  │
│  │  │               │◄──────┤                   │    │  │
│  │  │               │       │ - Ingress Rules   │    │  │
│  │  │  ┌─────────┐  │       │ - Egress Rules    │    │  │
│  │  │  │EBS Root │  │       └───────────────────┘    │  │
│  │  │  │ Volume  │  │                                │  │
│  │  │  └─────────┘  │                                │  │
│  │  │               │       ┌───────────────────┐    │  │
│  │  │  ┌─────────┐  │       │ IAM Role          │    │  │
│  │  │  │EBS Data │  │       │                   │    │  │
│  │  │  │ Volume  │  │◄──────┤ ┌─────────────┐   │    │  │
│  │  │  └─────────┘  │       │ │Instance     │   │    │  │
│  │  └───────────────┘       │ │Profile      │   │    │  │
│  │                          │ └─────────────┘   │    │  │
│  │                          └───────────────────┘    │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Usage

### Basic EC2 Instance

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ec2/webserver:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        
        # Instance Configuration
        instances:
          webserver:
            name: "web-server"
            ami_id: "ami-0c55b159cbfafe1f0"
            instance_type: "t3.micro"
            key_name: "my-ssh-key"
            subnet_id: ${dep.vpc.outputs.private_subnet_ids[0]}
            associate_public_ip: false
            root_volume_size: 20
            root_volume_type: "gp3"
            root_volume_encrypted: true
            enable_ssm: true
            user_data: |
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
            
            allowed_ingress_rules:
              - from_port: 80
                to_port: 80
                protocol: "tcp"
                cidr_blocks: ["10.0.0.0/16"]
                description: "Allow HTTP traffic"
              - from_port: 443
                to_port: 443
                protocol: "tcp"
                cidr_blocks: ["10.0.0.0/16"]
                description: "Allow HTTPS traffic"
                
            tags:
              Environment: dev
              Project: demo
```

### Multiple EC2 Instances

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ec2/workloads:
      vars:
        region: us-east-1
        vpc_id: ${dep.vpc.outputs.vpc_id}
        subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        
        # Instance Configuration
        instances:
          webserver:
            ami_id: "ami-0c55b159cbfafe1f0"
            instance_type: "t3.small"
            subnet_id: ${dep.vpc.outputs.private_subnet_ids[0]}
            root_volume_size: 20
            root_volume_encrypted: true
            enable_ssm: true
            custom_iam_policy: |
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Action": "s3:GetObject",
                    "Resource": "arn:aws:s3:::my-bucket/*"
                  }
                ]
              }
            allowed_ingress_rules:
              - from_port: 80
                to_port: 80
                protocol: "tcp"
                cidr_blocks: ["10.0.0.0/16"]
            
          appserver:
            ami_id: "ami-0c55b159cbfafe1f0"
            instance_type: "t3.medium"
            subnet_id: ${dep.vpc.outputs.private_subnet_ids[1]}
            root_volume_size: 50
            root_volume_encrypted: true
            ebs_block_devices:
              - device_name: "/dev/sdf"
                volume_size: 100
                volume_type: "gp3"
                encrypted: true
            allowed_ingress_rules:
              - from_port: 8080
                to_port: 8080
                protocol: "tcp"
                cidr_blocks: ["10.0.0.0/16"]
        
        tags:
          Environment: ${environment}
          Project: ${project}
          Owner: "Platform Team"
          ManagedBy: "Terraform"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `region` | AWS region | `string` | - | Yes |
| `vpc_id` | VPC ID where the instances will be created | `string` | - | Yes |
| `subnet_ids` | List of subnet IDs to launch the instances in | `list(string)` | - | Yes |
| `default_ami_id` | Default AMI ID to use if not specified per instance | `string` | `""` | No |
| `default_key_name` | Default key pair name for SSH access if not specified per instance | `string` | `null` | No |
| `instances` | Map of EC2 instance configurations | `map(any)` | `{}` | No |
| `tags` | Common tags to apply to all resources | `map(string)` | `{}` | No |

### Instance Configuration Options

Each instance in the `instances` map supports the following options:

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `ami_id` | AMI ID for the instance | `string` | Value of `default_ami_id` |
| `instance_type` | EC2 instance type | `string` | - |
| `key_name` | SSH key pair name | `string` | Value of `default_key_name` |
| `subnet_id` | Subnet ID for the instance | `string` | First subnet from `subnet_ids` |
| `additional_security_group_ids` | Additional security group IDs | `list(string)` | `[]` |
| `user_data` | User data script | `string` | `null` |
| `detailed_monitoring` | Enable detailed CloudWatch monitoring | `bool` | `false` |
| `ebs_optimized` | Enable EBS optimization | `bool` | `true` |
| `enabled` | Whether to create this instance | `bool` | `true` |
| `root_volume_type` | Root volume type | `string` | `"gp3"` |
| `root_volume_size` | Root volume size in GB | `number` | `20` |
| `root_volume_encrypted` | Encrypt root volume | `bool` | `true` |
| `root_volume_delete_on_termination` | Delete root volume on termination | `bool` | `true` |
| `root_volume_kms_key_id` | KMS key ID for root volume encryption | `string` | `null` |
| `ebs_block_devices` | Additional EBS volumes to attach | `list(map)` | `[]` |
| `allowed_ingress_rules` | Ingress rules for the instance security group | `list(map)` | `[]` |
| `enable_ssm` | Enable AWS Systems Manager | `bool` | `true` |
| `custom_iam_policy` | Custom IAM policy JSON | `string` | `""` |
| `tags` | Instance-specific tags | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_ids` | Map of instance names to their IDs |
| `instance_arns` | Map of instance names to their ARNs |
| `instance_public_ips` | Map of instance names to their public IP addresses |
| `instance_private_ips` | Map of instance names to their private IP addresses |
| `security_group_ids` | Map of instance names to their security group IDs |
| `iam_role_arns` | Map of instance names to their IAM role ARNs |
| `iam_role_names` | Map of instance names to their IAM role names |
| `iam_instance_profile_arns` | Map of instance names to their IAM instance profile ARNs |
| `iam_instance_profile_names` | Map of instance names to their IAM instance profile names |

## Features

### Security Group Management

Each EC2 instance gets its own security group with configurable ingress rules:

```yaml
instances:
  webserver:
    # ... other configuration ...
    allowed_ingress_rules:
      - from_port: 80
        to_port: 80
        protocol: "tcp"
        cidr_blocks: ["10.0.0.0/16"]
        description: "Allow HTTP traffic"
      - from_port: 443
        to_port: 443
        protocol: "tcp"
        security_groups: ["sg-12345678"]
        description: "Allow HTTPS traffic from specific security group"
```

### EBS Volume Management

Configure the root volume and add additional EBS volumes:

```yaml
instances:
  dataserver:
    # ... other configuration ...
    root_volume_size: 50
    root_volume_type: "gp3"
    root_volume_encrypted: true
    
    ebs_block_devices:
      - device_name: "/dev/sdf"
        volume_size: 100
        volume_type: "gp3"
        encrypted: true
      - device_name: "/dev/sdg"
        volume_size: 500
        volume_type: "st1"
        encrypted: true
```

### IAM Role and SSM Integration

Each instance gets an IAM role and instance profile with SSM access by default, which can be extended with custom policies:

```yaml
instances:
  webserver:
    # ... other configuration ...
    enable_ssm: true
    custom_iam_policy: |
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "s3:GetObject",
              "s3:ListBucket"
            ],
            "Resource": [
              "arn:aws:s3:::my-app-configs",
              "arn:aws:s3:::my-app-configs/*"
            ]
          }
        ]
      }
```

## Best Practices

### Security

1. **Private Subnets**: Deploy instances in private subnets and use a bastion host or SSM Session Manager for access
2. **Security Groups**: Apply least-privilege security group rules
3. **Encryption**: Enable encryption for all EBS volumes
4. **IAM Roles**: Use instance profiles with minimal permissions
5. **Patching**: Keep instances updated with security patches through SSM Patch Manager
6. **Systems Manager**: Use SSM instead of SSH key pairs for secure instance access

### Cost Optimization

1. **Right Sizing**: Choose appropriate instance types for your workloads
2. **GP3 Volumes**: Use gp3 volume type for better performance and lower cost
3. **Lifecycle Management**: Use lifecycle rules to properly terminate instances
4. **Reserved Instances**: Consider reserved instances for predictable workloads
5. **Monitoring**: Enable detailed monitoring only when necessary

### Performance

1. **EBS Optimization**: Keep EBS optimization enabled for better disk performance
2. **Instance Placement**: Use placement groups for high-performance workloads
3. **Network Performance**: Choose instances with appropriate network performance
4. **Volume IOPS**: Configure appropriate IOPS for your workload needs

## Troubleshooting

### Common Issues

1. **Connection Issues**

   If you can't connect to instances:
   
   - Verify security group allows necessary traffic
   - Check if instance is in a private subnet without proper NAT gateway
   - For SSM connection issues, verify SSM agent is running and IAM role is correct

   ```bash
   # Check SSM connection status
   aws ssm describe-instance-information
   
   # Start SSM session (instead of SSH)
   aws ssm start-session --target i-1234567890abcdef0
   ```

2. **Volume Mounting Problems**

   If additional EBS volumes aren't properly mounted:
   
   ```bash
   # List available block devices
   lsblk
   
   # Format volume (if new)
   sudo mkfs -t xfs /dev/nvme1n1
   
   # Mount volume
   sudo mkdir -p /data
   sudo mount /dev/nvme1n1 /data
   ```

3. **User Data Script Issues**

   To debug user data script issues:
   
   ```bash
   # Check cloud-init logs
   sudo cat /var/log/cloud-init.log
   sudo cat /var/log/cloud-init-output.log
   ```

### Validation Commands

```bash
# Validate component configuration
atmos terraform validate ec2/webserver -s mycompany-dev-us-east-1

# View plan for the component
atmos terraform plan ec2/webserver -s mycompany-dev-us-east-1

# Get component outputs after deployment
atmos terraform output ec2/webserver -s mycompany-dev-us-east-1
```

## Related Components

- **vpc** - For setting up the VPC where instances will be deployed
- **securitygroup** - For creating shared security groups
- **iam** - For creating IAM roles and policies
- **kms** - For creating KMS keys for volume encryption
- **alb** - For creating Application Load Balancers to distribute traffic to instances

## Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html)
- [AWS Systems Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html)
- [EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [EBS Volume Types](https://aws.amazon.com/ebs/volume-types/)