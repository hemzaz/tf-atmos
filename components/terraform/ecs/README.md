# ECS Component

This component creates and manages Amazon Elastic Container Service (ECS) resources, including clusters, services, task definitions, and capacity providers.

## Features

- Create and manage ECS clusters with Fargate and EC2 launch types
- Deploy ECS services with auto-scaling
- Define task definitions with container configurations
- Support for service discovery
- Capacity provider strategies
- Load balancer integration
- CloudWatch logging
- EFS volume mounts
- Blue/green deployments with CodeDeploy
- Task execution and task IAM roles

## Usage

```hcl
module "ecs" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/ecs"
  
  region = var.region
  
  # ECS Cluster
  cluster_name = "app-cluster"
  
  # Capacity Providers
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]
  
  # Task Definition
  task_definition = {
    family                   = "app-service"
    requires_compatibilities = ["FARGATE"]
    network_mode             = "awsvpc"
    cpu                      = 1024
    memory                   = 2048
    execution_role_arn       = aws_iam_role.ecs_execution_role.arn
    task_role_arn            = aws_iam_role.ecs_task_role.arn
    
    container_definitions = jsonencode([
      {
        name              = "app"
        image             = "123456789012.dkr.ecr.us-west-2.amazonaws.com/app:latest"
        essential         = true
        cpu               = 1024
        memory            = 2048
        logConfiguration  = {
          logDriver = "awslogs"
          options   = {
            "awslogs-group"         = "/ecs/app-service"
            "awslogs-region"        = "us-west-2"
            "awslogs-stream-prefix" = "app"
          }
        }
        portMappings     = [
          {
            containerPort = 8080
            hostPort      = 8080
            protocol      = "tcp"
          }
        ]
        environment = [
          {
            name  = "ENVIRONMENT"
            value = "production"
          }
        ]
        secrets = [
          {
            name      = "DATABASE_PASSWORD"
            valueFrom = "arn:aws:secretsmanager:us-west-2:123456789012:secret:db-password:password::"
          }
        ]
      }
    ])
  }
  
  # ECS Service
  service = {
    name            = "app-service"
    desired_count   = 2
    launch_type     = ""  # Empty for capacity provider
    propagate_tags  = "SERVICE"
    enable_execute_command = true
    
    capacity_provider_strategy = [
      {
        capacity_provider = "FARGATE"
        weight            = 1
        base              = 1
      }
    ]
    
    network_configuration = {
      subnets          = ["subnet-12345678", "subnet-87654321"]
      security_groups  = ["sg-12345678"]
      assign_public_ip = false
    }
    
    load_balancer = {
      target_group_arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/app-tg/abcdef0123456789"
      container_name   = "app"
      container_port   = 8080
    }
    
    service_registries = {
      registry_arn = "arn:aws:servicediscovery:us-west-2:123456789012:service/srv-abcdef0123456789"
    }
    
    deployment_circuit_breaker = {
      enable   = true
      rollback = true
    }
    
    deployment_controller = {
      type = "ECS"  # Can be ECS, CODE_DEPLOY, or EXTERNAL
    }
    
    auto_scaling = {
      max_capacity       = 10
      min_capacity       = 2
      target_cpu_value   = 70
      target_memory_value = 0
      scale_in_cooldown  = 300
      scale_out_cooldown = 60
    }
  }
  
  # Global Tags
  tags = {
    Environment = "production"
    Project     = "example"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| cluster_name | Name of the ECS cluster | `string` | n/a | yes |
| capacity_providers | List of capacity providers | `list(string)` | `["FARGATE", "FARGATE_SPOT"]` | no |
| default_capacity_provider_strategy | Default capacity provider strategy for the cluster | `list(map(any))` | `[]` | no |
| task_definition | Task definition configuration | `any` | n/a | yes |
| service | Service configuration | `any` | n/a | yes |
| create_task_execution_role | Whether to create task execution IAM role | `bool` | `false` | no |
| create_task_role | Whether to create task IAM role | `bool` | `false` | no |
| cloudwatch_log_group_name | Name of the CloudWatch log group | `string` | `""` | no |
| cloudwatch_log_retention_days | Number of days to retain CloudWatch logs | `number` | `30` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | The Amazon Resource Name (ARN) of the ECS cluster |
| cluster_name | The name of the ECS cluster |
| service_id | The Amazon Resource Name (ARN) of the ECS service |
| service_name | The name of the ECS service |
| task_definition_arn | The full ARN of the task definition |
| task_definition_family | The family of the task definition |
| task_execution_role_arn | The ARN of the task execution IAM role |
| task_role_arn | The ARN of the task IAM role |

## Examples

### Basic Fargate Service

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ecs/app-service:
      vars:
        region: us-west-2
        
        # ECS Cluster
        cluster_name: "app-cluster"
        
        # Capacity Providers
        capacity_providers: ["FARGATE"]
        default_capacity_provider_strategy:
          - capacity_provider: "FARGATE"
            weight: 1
            base: 1
        
        # Task Definition
        task_definition:
          family: "app-service"
          requires_compatibilities: ["FARGATE"]
          network_mode: "awsvpc"
          cpu: 1024
          memory: 2048
          execution_role_arn: ${dep.iam.outputs.ecs_execution_role_arn}
          task_role_arn: ${dep.iam.outputs.ecs_task_role_arn}
          
          container_definitions: |
            [
              {
                "name": "app",
                "image": "${dep.ecr.outputs.repository_url}:latest",
                "essential": true,
                "cpu": 1024,
                "memory": 2048,
                "logConfiguration": {
                  "logDriver": "awslogs",
                  "options": {
                    "awslogs-group": "/ecs/app-service",
                    "awslogs-region": "us-west-2",
                    "awslogs-stream-prefix": "app"
                  }
                },
                "portMappings": [
                  {
                    "containerPort": 8080,
                    "hostPort": 8080,
                    "protocol": "tcp"
                  }
                ],
                "environment": [
                  {
                    "name": "ENVIRONMENT",
                    "value": "production"
                  }
                ],
                "secrets": [
                  {
                    "name": "DATABASE_URL",
                    "valueFrom": "${dep.secretsmanager.outputs.db_url_secret_arn}"
                  }
                ]
              }
            ]
        
        # CloudWatch Logs
        cloudwatch_log_group_name: "/ecs/app-service"
        cloudwatch_log_retention_days: 30
        
        # ECS Service
        service:
          name: "app-service"
          desired_count: 2
          launch_type: ""  # Empty for capacity provider
          propagate_tags: "SERVICE"
          enable_execute_command: true
          
          capacity_provider_strategy:
            - capacity_provider: "FARGATE"
              weight: 1
              base: 1
          
          network_configuration:
            subnets: ${dep.vpc.outputs.private_subnet_ids}
            security_groups: ["${dep.securitygroup.outputs.app_security_group_id}"]
            assign_public_ip: false
          
          load_balancer:
            target_group_arn: ${dep.apigateway.outputs.target_group_arn}
            container_name: "app"
            container_port: 8080
          
          service_registries:
            registry_arn: ${dep.servicediscovery.outputs.service_arn}
          
          deployment_circuit_breaker:
            enable: true
            rollback: true
          
          deployment_controller:
            type: "ECS"
          
          auto_scaling:
            max_capacity: 10
            min_capacity: 2
            target_cpu_value: 70
            target_memory_value: 0
            scale_in_cooldown: 300
            scale_out_cooldown: 60
        
        # Tags
        tags:
          Environment: production
          Project: app-service
```

### ECS with EC2 Launch Type

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ecs/ec2-service:
      vars:
        region: us-west-2
        
        # ECS Cluster
        cluster_name: "ec2-cluster"
        
        # Task Definition
        task_definition:
          family: "batch-processor"
          requires_compatibilities: ["EC2"]
          network_mode: "bridge"
          cpu: 1024
          memory: 2048
          execution_role_arn: ${dep.iam.outputs.ecs_execution_role_arn}
          task_role_arn: ${dep.iam.outputs.ecs_task_role_arn}
          
          container_definitions: |
            [
              {
                "name": "processor",
                "image": "${dep.ecr.outputs.repository_url}:latest",
                "essential": true,
                "cpu": 1024,
                "memory": 2048,
                "logConfiguration": {
                  "logDriver": "awslogs",
                  "options": {
                    "awslogs-group": "/ecs/batch-processor",
                    "awslogs-region": "us-west-2",
                    "awslogs-stream-prefix": "processor"
                  }
                },
                "environment": [
                  {
                    "name": "ENVIRONMENT",
                    "value": "production"
                  }
                ],
                "mountPoints": [
                  {
                    "sourceVolume": "data",
                    "containerPath": "/data",
                    "readOnly": false
                  }
                ]
              }
            ]
          
          volumes:
            - name: "data"
              efs_volume_configuration:
                file_system_id: ${dep.efs.outputs.file_system_id}
                root_directory: "/"
        
        # CloudWatch Logs
        cloudwatch_log_group_name: "/ecs/batch-processor"
        cloudwatch_log_retention_days: 14
        
        # ECS Service
        service:
          name: "batch-processor"
          desired_count: 2
          launch_type: "EC2"
          
          placement_constraints:
            - type: "memberOf"
              expression: "attribute:ecs.instance-type =~ t3.*"
          
          ordered_placement_strategy:
            - type: "spread"
              field: "attribute:ecs.availability-zone"
            - type: "binpack"
              field: "memory"
          
          deployment_circuit_breaker:
            enable: true
            rollback: true
          
          deployment_controller:
            type: "ECS"
          
          auto_scaling:
            max_capacity: 5
            min_capacity: 1
            target_cpu_value: 70
            scale_in_cooldown: 300
            scale_out_cooldown: 60
        
        # Tags
        tags:
          Environment: production
          Project: batch-processor
```

### Blue/Green Deployment with CodeDeploy

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    ecs/blue-green-service:
      vars:
        region: us-west-2
        
        # ECS Cluster
        cluster_name: "app-cluster"
        
        # Capacity Providers
        capacity_providers: ["FARGATE"]
        default_capacity_provider_strategy:
          - capacity_provider: "FARGATE"
            weight: 1
            base: 1
        
        # Task Definition
        task_definition:
          family: "web-app"
          requires_compatibilities: ["FARGATE"]
          network_mode: "awsvpc"
          cpu: 1024
          memory: 2048
          execution_role_arn: ${dep.iam.outputs.ecs_execution_role_arn}
          task_role_arn: ${dep.iam.outputs.ecs_task_role_arn}
          
          container_definitions: |
            [
              {
                "name": "web",
                "image": "${dep.ecr.outputs.repository_url}:latest",
                "essential": true,
                "cpu": 1024,
                "memory": 2048,
                "logConfiguration": {
                  "logDriver": "awslogs",
                  "options": {
                    "awslogs-group": "/ecs/web-app",
                    "awslogs-region": "us-west-2",
                    "awslogs-stream-prefix": "web"
                  }
                },
                "portMappings": [
                  {
                    "containerPort": 80,
                    "hostPort": 80,
                    "protocol": "tcp"
                  }
                ]
              }
            ]
        
        # CloudWatch Logs
        cloudwatch_log_group_name: "/ecs/web-app"
        cloudwatch_log_retention_days: 30
        
        # ECS Service
        service:
          name: "web-app"
          desired_count: 2
          launch_type: ""  # Empty for capacity provider
          propagate_tags: "SERVICE"
          
          capacity_provider_strategy:
            - capacity_provider: "FARGATE"
              weight: 1
              base: 1
          
          network_configuration:
            subnets: ${dep.vpc.outputs.private_subnet_ids}
            security_groups: ["${dep.securitygroup.outputs.web_security_group_id}"]
            assign_public_ip: false
          
          load_balancer:
            target_group_arn: ${dep.alb.outputs.blue_target_group_arn}
            container_name: "web"
            container_port: 80
          
          deployment_controller:
            type: "CODE_DEPLOY"
          
          # CodeDeploy configuration must be set up separately
        
        # Tags
        tags:
          Environment: production
          Project: web-app
```

## Implementation Best Practices

1. **Security**:
   - Use IAM roles with least privilege permissions
   - Store sensitive information in Secrets Manager or SSM Parameter Store
   - Run containers in private subnets
   - Use security groups to restrict network access
   - Enable execution command with appropriate controls
   - Encrypt data at rest and in transit

2. **Reliability**:
   - Use deployment circuit breakers to detect and roll back failed deployments
   - Configure health checks for your services
   - Implement auto-scaling based on CPU/memory utilization
   - Use service discovery for inter-service communication
   - Implement retry logic and idempotent operations in your applications

3. **Performance**:
   - Choose appropriate CPU and memory for your tasks
   - Optimize container images for size and startup time
   - Use placement strategies for EC2 launch type to optimize resource utilization
   - Consider using Service Connect for service mesh capabilities
   - Implement task burst capabilities for handling traffic spikes

4. **Cost Optimization**:
   - Implement auto-scaling to match capacity with demand
   - Choose appropriate task sizes to avoid over-provisioning
   - Monitor resource utilization and adjust allocation
   - Consider using Compute Savings Plans for predictable workloads
   - Use appropriate storage for container images