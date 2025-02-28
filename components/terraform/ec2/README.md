# EC2 Component

This component provisions and manages AWS EC2 instances and related resources including security groups, volumes, and instance profiles.

## Features

- Provision EC2 instances with configurable instance types, AMIs, and user data
- Attach EBS volumes with customizable sizes and types
- Create instance profiles with IAM roles
- Configure security groups and network settings
- Set up instance monitoring and CloudWatch alarms
- Support for spot instances
- Deploy auto-scaling groups

## Usage

```hcl
module "ec2" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/ec2"
  
  region = var.region
  
  # Instance Configuration
  instances = {
    "webserver" = {
      name                   = "web-server"
      ami                    = "ami-0c55b159cbfafe1f0"
      instance_type          = "t3.medium"
      key_name               = "my-ssh-key"
      subnet_id              = "subnet-12345678"
      vpc_security_group_ids = ["sg-12345678"]
      associate_public_ip    = true
      root_volume_size       = 20
      root_volume_type       = "gp3"
      ebs_volumes = {
        "data" = {
          device_name = "/dev/sdf"
          volume_size = 100
          volume_type = "gp3"
          encrypted   = true
        }
      }
      user_data = <<-EOT
        #!/bin/bash
        yum update -y
        yum install -y httpd
        systemctl start httpd
        systemctl enable httpd
      EOT
      iam_instance_profile = "WebServerProfile"
      monitoring           = true
      tags = {
        Name        = "web-server"
        Environment = "production"
      }
    }
  }
  
  # Auto Scaling Group Configuration
  auto_scaling_groups = {
    "webapp" = {
      name                = "webapp-asg"
      min_size            = 2
      max_size            = 10
      desired_capacity    = 2
      vpc_zone_identifier = ["subnet-12345678", "subnet-87654321"]
      launch_template = {
        name          = "webapp-lt"
        ami           = "ami-0c55b159cbfafe1f0"
        instance_type = "t3.medium"
        key_name      = "my-ssh-key"
        user_data     = "IyEvYmluL2Jhc2gKeXVtIHVwZGF0ZSAteQp5dW0gaW5zdGFsbCAteSBodHRwZA=="
        block_device_mappings = [
          {
            device_name = "/dev/sda1"
            ebs = {
              volume_size = 20
              volume_type = "gp3"
            }
          }
        ]
        network_interfaces = [
          {
            security_groups             = ["sg-12345678"]
            associate_public_ip_address = true
          }
        ]
        iam_instance_profile = {
          name = "AppServerProfile"
        }
      }
      
      # Scaling Policies
      scaling_policies = {
        "cpu-policy" = {
          name                   = "cpu-scaling-policy"
          policy_type            = "TargetTrackingScaling"
          estimated_instance_warmup = 300
          target_tracking_configuration = {
            predefined_metric_specification = {
              predefined_metric_type = "ASGAverageCPUUtilization"
            }
            target_value = 70.0
          }
        }
      }
      
      tags = [
        {
          key                 = "Name"
          value               = "webapp-asg"
          propagate_at_launch = true
        },
        {
          key                 = "Environment"
          value               = "production"
          propagate_at_launch = true
        }
      ]
    }
  }
  
  # Global Tags
  tags = {
    Project     = "example"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| instances | Map of EC2 instance configurations | `map(any)` | `{}` | no |
| auto_scaling_groups | Map of auto scaling group configurations | `map(any)` | `{}` | no |
| create_security_group | Whether to create a security group for the instances | `bool` | `false` | no |
| security_group_rules | List of security group rules to add to the instance security group | `list(any)` | `[]` | no |
| create_iam_instance_profile | Whether to create an IAM instance profile | `bool` | `false` | no |
| iam_role_policy_arns | List of IAM policy ARNs to attach to the instance profile | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_ids | Map of instance names to their IDs |
| instance_public_ips | Map of instance names to their public IPs |
| instance_private_ips | Map of instance names to their private IPs |
| auto_scaling_group_names | Map of auto scaling group names to their ARNs |
| auto_scaling_group_ids | Map of auto scaling group names to their IDs |
| security_group_id | ID of the security group created for the instances |
| iam_instance_profile_name | Name of the IAM instance profile created |
| iam_instance_profile_arn | ARN of the IAM instance profile created |

## Examples

### Basic EC2 Instance

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ec2/webserver:
      vars:
        region: us-west-2
        
        # Instance Configuration
        instances:
          webserver:
            name: "web-server"
            ami: "ami-0c55b159cbfafe1f0"
            instance_type: "t3.micro"
            key_name: "my-ssh-key"
            subnet_id: ${dep.vpc.outputs.public_subnet_ids[0]}
            vpc_security_group_ids: [${dep.securitygroup.outputs.web_security_group_id}]
            associate_public_ip: true
            root_volume_size: 20
            root_volume_type: "gp3"
            user_data: |
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
            
            tags:
              Environment: dev
              Project: demo
```

### EC2 Instances with Auto Scaling

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ec2/webapp:
      vars:
        region: us-west-2
        
        # Auto Scaling Group Configuration
        auto_scaling_groups:
          webapp:
            name: "webapp-asg"
            min_size: 2
            max_size: 10
            desired_capacity: 2
            vpc_zone_identifier: ${dep.vpc.outputs.private_subnet_ids}
            
            launch_template:
              name: "webapp-lt"
              ami: "ami-0c55b159cbfafe1f0"
              instance_type: "t3.medium"
              key_name: "my-ssh-key"
              user_data_base64: "${base64encode(file("./scripts/userdata.sh"))}"
              
              block_device_mappings:
                - device_name: "/dev/sda1"
                  ebs:
                    volume_size: 20
                    volume_type: "gp3"
                    encrypted: true
              
              network_interfaces:
                - security_groups: [${dep.securitygroup.outputs.app_security_group_id}]
                  associate_public_ip_address: false
              
              iam_instance_profile:
                name: ${dep.iam.outputs.app_instance_profile_name}
            
            # Scaling Policies
            scaling_policies:
              cpu-policy:
                name: "cpu-scaling-policy"
                policy_type: "TargetTrackingScaling"
                estimated_instance_warmup: 300
                target_tracking_configuration:
                  predefined_metric_specification:
                    predefined_metric_type: "ASGAverageCPUUtilization"
                  target_value: 70.0
            
            tags:
              - key: "Name"
                value: "webapp-asg"
                propagate_at_launch: true
              - key: "Environment"
                value: "production"
                propagate_at_launch: true
```


## Best Practices

1. **Security**:
   - Use security groups to restrict network access
   - Enable encryption for EBS volumes
   - Use IAM instance profiles with least privilege permissions
   - Keep AMIs updated with security patches
   - Deploy instances in private subnets unless public access is required

2. **High Availability**:
   - Use auto-scaling groups to maintain application availability
   - Distribute instances across multiple Availability Zones
   - Implement health checks and automatic recovery
   - Use Elastic Load Balancers for distributing traffic

3. **Cost Optimization**:
   - Use auto-scaling to match capacity with demand
   - Select appropriate instance types and sizes for workloads
   - Use gp3 volumes instead of gp2 for better price/performance
   - Consider reserved instances for predictable workloads
   - Enable detailed monitoring only when necessary

4. **Operational Excellence**:
   - Use standardized AMIs with pre-installed applications and configurations
   - Implement consistent tagging for resources
   - Use user data scripts for predictable instance initialization
   - Consider using Systems Manager for instance management
   - Implement monitoring and alerting for instance health