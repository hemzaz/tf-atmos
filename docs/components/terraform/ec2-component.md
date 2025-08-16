# EC2 Component

_Last Updated: March 1, 2025_

## Overview

A versatile AWS EC2 infrastructure component for Atmos that manages EC2 instances, security groups, IAM roles, and related resources for your cloud workloads.

This component provides a flexible way to deploy and manage AWS EC2 resources including:

- EC2 instances with customizable configurations
- Security groups with configurable rules
- IAM roles and instance profiles with proper permissions
- EBS volumes with customizable sizes and types
- System Manager integration for secure instance management
- Detailed resource tagging and naming conventions
- **SSH key pair generation and management** (with AWS Secrets Manager integration)

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
| `global_key_name` | Name for a global SSH key that will be used by instances not specifying their own key | `string` | `null` | No |
| `create_ssh_keys` | Whether to create SSH key pairs when not specified | `bool` | `false` | No |
| `store_ssh_keys_in_secrets_manager` | Whether to store generated SSH keys in AWS Secrets Manager | `bool` | `true` | No |
| `ssh_key_algorithm` | Algorithm for SSH key generation (RSA, ED25519) | `string` | `"RSA"` | No |
| `ssh_key_rsa_bits` | Bit size for RSA keys | `number` | `4096` | No |
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
| `generated_key_names` | Map of instance names (including "global") to their generated SSH key names |
| `ssh_key_secret_arns` | Map of instance names (including "global") to Secret Manager ARNs containing SSH keys |
| `global_key_name` | Name of the generated global SSH key, if created |
| `global_key_secret_arn` | ARN of the Secret Manager secret containing the global SSH key, if created |
| `instances_using_global_key` | List of instance names using the global SSH key |
| `instances_using_individual_keys` | List of instance names using individually generated SSH keys |

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

### SSH Key Management

The component supports three flexible approaches to SSH key management:

1. **Global SSH Key**: One key shared by multiple instances in an environment
2. **Individual SSH Keys**: Unique key for each instance
3. **Existing SSH Keys**: Reference existing AWS key pairs

#### Configuration Options

```yaml
# Component configuration
ec2:
  vars:
    # ... other configuration ...
    create_ssh_keys: true
    store_ssh_keys_in_secrets_manager: true
    ssh_key_algorithm: "RSA"  # Supports RSA or ED25519
    ssh_key_rsa_bits: 4096    # For RSA keys
    
    # Use a global key for instances that don't specify their own key
    global_key_name: "myenv-shared-key"
    
    # OR use an existing key as the default
    # default_key_name: "existing-key-pair"
    
    instances:
      webserver:
        # Will use the global key as no key_name is specified
        instance_type: "t3.micro"
        
      database:
        # Use an existing key pair
        key_name: "existing-key-pair"
        instance_type: "t3.small"
        
      app_server:
        # Force creation of an individual key by explicitly setting to null
        key_name: null
        instance_type: "t3.medium"
```

#### Key Selection Logic

The component uses the following logic to determine which SSH key to use for each instance:

1. If the instance has an explicit `key_name` specified (not null):
   - Use the specified existing key pair
2. If the instance has `key_name: null` specified explicitly:
   - Generate an individual key for this instance
3. If no `key_name` is specified and `global_key_name` is defined:
   - Use the shared global key for the environment
4. If no `key_name` is specified and `default_key_name` is defined:
   - Use the specified default key pair
5. If no `key_name` is specified and neither `global_key_name` nor `default_key_name` are defined:
   - Generate an individual key for this instance

#### Secure Storage in Secrets Manager

Generated keys are stored in AWS Secrets Manager with the following path structures:

- **Individual Keys**: `ssh-key/{environment}/{instance-name}`
- **Global Key**: `ssh-key/{environment}/global-keys/{global-key-name}`

The secret values are stored in JSON format:

```json
// Individual key format - initial creation
{
  "private_key_pem": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "public_key_openssh": "ssh-rsa AAAAB3NzaC1yc2EAAA...",
  "key_name": "env-instance-key",
  "instance_name": "instance-name"
}

// Individual key format - after instance creation
{
  "private_key_pem": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "public_key_openssh": "ssh-rsa AAAAB3NzaC1yc2EAAA...",
  "key_name": "env-instance-key",
  "instance_name": "instance-name",
  "instance_id": "i-0123456789abcdef0"  // Added after instance creation
}

// Global key format - initial creation
{
  "private_key_pem": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "public_key_openssh": "ssh-rsa AAAAB3NzaC1yc2EAAA...",
  "key_name": "env-global-key-name",
  "environment": "environment-name",
  "used_by_instances": ["instance1", "instance2", "instance3"]
}

// Global key format - after instances creation
{
  "private_key_pem": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "public_key_openssh": "ssh-rsa AAAAB3NzaC1yc2EAAA...",
  "key_name": "env-global-key-name",
  "environment": "environment-name",
  "used_by_instances": ["instance1", "instance2", "instance3"],
  "instance_details": {  // Added after instances creation
    "instance1": "i-0123456789abcdef0",
    "instance2": "i-0123456789abcdef1",
    "instance3": "i-0123456789abcdef2"
  }
}
```

#### Retrieving SSH Keys

To retrieve an individual key for an instance:

```bash
# Get individual SSH key
aws secretsmanager get-secret-value \
  --secret-id ssh-key/environment-name/instance-name \
  --query SecretString --output text | jq -r '.private_key_pem' > instance_key.pem

chmod 400 instance_key.pem
ssh -i instance_key.pem ec2-user@instance-ip-address
```

To retrieve a global key used by multiple instances:

```bash
# Get global SSH key
aws secretsmanager get-secret-value \
  --secret-id ssh-key/environment-name/global-keys/global-key-name \
  --query SecretString --output text | jq -r '.private_key_pem' > global_key.pem

chmod 400 global_key.pem
ssh -i global_key.pem ec2-user@instance-ip-address
```

> **Note**: The commands above require [jq](https://stedolan.github.io/jq/) to be installed. If you don't have jq, you can store the JSON in a file and extract the key manually.

## Best Practices

### Security

1. **Private Subnets**: Deploy instances in private subnets and use a bastion host or SSM Session Manager for access
2. **Security Groups**: Apply least-privilege security group rules
3. **Encryption**: Enable encryption for all EBS volumes
4. **IAM Roles**: Use instance profiles with minimal permissions
5. **Patching**: Keep instances updated with security patches through SSM Patch Manager
6. **Systems Manager**: Use SSM instead of SSH key pairs for secure instance access when possible
7. **SSH Keys**: When SSH keys are needed, let the component generate them and store in Secrets Manager
8. **Global Keys**: Use a global key for environments where key management is simpler, with individual keys for privileged instances
9. **Key Access Control**: Use IAM policies to restrict access to SSH keys in Secrets Manager:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "secretsmanager:GetSecretValue"
         ],
         "Resource": [
           "arn:aws:secretsmanager:*:*:secret:ssh-key/production/bastion-*"
         ]
       }
     ]
   }
   ```

10. **Key Rotation**: Implement periodic rotation of SSH keys through Secrets Manager rotation policies or scheduled updates

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

## Advanced Topics

### SSH Key Rotation

While the component is designed to create stable, persistent SSH keys, you may want to rotate keys periodically for security reasons. Here are some approaches:

1. **Manual Key Rotation**:
   - Set `create_ssh_keys = false` temporarily
   - Run `terraform apply` to disable key creation
   - Delete the secret from AWS Secrets Manager
   - Delete the key pair from AWS
   - Set `create_ssh_keys = true` again
   - Run `terraform apply` to create new keys

2. **Automated Rotation Using Lambda**:
   - Create a Lambda function for key rotation
   - Configure Secrets Manager rotation
   - Update instance userdata to retrieve the latest key

### Key Recovery

If you accidentally delete a SSH key secret:

1. **For Individual Keys**:
   - If the key pair still exists in AWS, create a new secret manually with the same name path
   - If the key pair is gone, you'll need to recreate it by temporarily removing the `prevent_destroy` lifecycle rule and running `terraform apply`

2. **For Global Keys**:
   - Follow the same process as individual keys
   - Update all instances that use the global key

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