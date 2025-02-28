# Amazon ECS Component

_Last Updated: February 28, 2025_

## Overview

A comprehensive Amazon Elastic Container Service (ECS) component for Atmos that creates and manages ECS clusters, services, task definitions, and capacity providers.

This component creates a complete ECS infrastructure including:

- ECS clusters with customizable settings
- Support for both Fargate and EC2 launch types
- Capacity providers and capacity provider strategies
- Container Insights for monitoring
- Auto-scaling group integration for EC2 launch type
- Managed scaling configuration

## Architecture

The diagram below illustrates the architecture created by this component:

```
                              +-------------------+
                              |   Load Balancer   |
                              +--------+----------+
                                       |
                                       v
          +--------------------------------------------------+
          |                   ECS Cluster                    |
          |                                                  |
          |  +----------------+       +------------------+   |
          |  |                |       |                  |   |
          |  | Fargate Tasks  |       |   EC2 Instances  |   |
          |  |                |       |                  |   |
          |  +----------------+       +------------------+   |
          |                                  ^               |
          |                                  |               |
          |                           +------+----------+    |
          |                           | Auto Scaling    |    |
          |                           | Group           |    |
          |                           +-----------------+    |
          |                                                  |
          |  +---------------------------------------+       |
          |  |          Capacity Providers           |       |
          |  | - FARGATE                            |       |
          |  | - FARGATE_SPOT                       |       |
          |  | - Custom EC2 Capacity Provider       |       |
          |  +---------------------------------------+       |
          |                                                  |
          |  +---------------------------------------+       |
          |  |       Container Insights (Optional)   |       |
          |  +---------------------------------------+       |
          +--------------------------------------------------+
```

## Features

- **Cluster Management**: Create and manage ECS clusters with configurable settings
- **Flexible Launch Options**: Support for Fargate, Fargate Spot, and EC2 launch types
- **Capacity Provider Management**: Create and configure capacity providers
- **Capacity Provider Strategies**: Define default capacity provider strategies
- **Autoscaling Integration**: Connect ECS with EC2 Auto Scaling Groups
- **Managed Scaling**: Configure managed scaling parameters for capacity providers
- **Container Insights**: Enable/disable Container Insights for monitoring
- **Resource Tagging**: Comprehensive tagging for all created resources

## Usage

### Basic Fargate Cluster

```yaml
components:
  terraform:
    ecs/web:
      vars:
        region: us-west-2
        fargate_only: true
        enable_container_insights: true
        tags:
          Environment: production
          Application: web
```

### EC2 and Fargate Hybrid Cluster

```yaml
components:
  terraform:
    ecs/hybrid:
      vars:
        region: us-west-2
        fargate_only: false
        autoscaling_group_arn: ${dependency.autoscaling.outputs.autoscaling_group_arn}
        max_scaling_step_size: 5
        min_scaling_step_size: 1
        target_capacity: 80
        enable_container_insights: true
        tags:
          Environment: production
          Application: backend
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `region` | AWS region | `string` | - | Yes |
| `fargate_only` | Whether to use only Fargate for the ECS cluster | `bool` | `true` | No |
| `autoscaling_group_arn` | ARN of the Auto Scaling Group to use with the cluster | `string` | `""` | No |
| `max_scaling_step_size` | Maximum step size for ECS managed scaling | `number` | `10` | No |
| `min_scaling_step_size` | Minimum step size for ECS managed scaling | `number` | `1` | No |
| `target_capacity` | Target capacity for ECS managed scaling (percentage) | `number` | `100` | No |
| `enable_container_insights` | Enable Container Insights for the ECS cluster | `bool` | `true` | No |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_id` | The ID of the ECS cluster |
| `cluster_arn` | The ARN of the ECS cluster |
| `cluster_name` | The name of the ECS cluster |
| `capacity_providers` | List of capacity providers in the cluster |

## How It Works

### Cluster Creation

The component creates an ECS cluster with the provided configuration:

```hcl
resource "aws_ecs_cluster" "main" {
  name = "${var.tags["Environment"]}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-ecs-cluster"
    }
  )
}
```

### Capacity Provider Configuration

For clusters that use EC2 instances, a capacity provider is created and linked to the specified Auto Scaling Group:

```hcl
resource "aws_ecs_capacity_provider" "main" {
  count = var.fargate_only ? 0 : 1
  name  = "${var.tags["Environment"]}-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = var.autoscaling_group_arn

    managed_scaling {
      maximum_scaling_step_size = var.max_scaling_step_size
      minimum_scaling_step_size = var.min_scaling_step_size
      status                    = "ENABLED"
      target_capacity           = var.target_capacity
    }
  }
}
```

### Default Capacity Provider Strategy

The component configures a default capacity provider strategy for the cluster:

```hcl
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = concat(
    var.fargate_only ? [] : [aws_ecs_capacity_provider.main[0].name],
    ["FARGATE", "FARGATE_SPOT"]
  )

  default_capacity_provider_strategy {
    capacity_provider = var.fargate_only ? "FARGATE" : aws_ecs_capacity_provider.main[0].name
    weight            = 1
  }
}
```

## Best Practices

### Fargate vs EC2 Launch Type

- **Fargate**: Best for applications where you don't want to manage the underlying infrastructure
  - Lower operational overhead
  - Good for predictable workloads
  - Higher per-task cost

- **EC2**: Best for applications with specific hardware requirements or cost optimization
  - Lower per-task cost for high utilization
  - More control over the underlying infrastructure
  - Higher operational overhead

### Container Insights

Enable Container Insights in production environments for comprehensive monitoring:

```yaml
enable_container_insights: true
```

### Capacity Provider Strategy

- Use FARGATE_SPOT for non-critical workloads to reduce costs
- For production workloads requiring high availability, use a combination of FARGATE and EC2 instances
- Configure appropriate target capacity to optimize resource utilization

### Autoscaling Configuration

- Set reasonable `min_scaling_step_size` and `max_scaling_step_size` based on your workload patterns
- Configure `target_capacity` based on your application's resource utilization patterns (typically 70-80% is a good balance)

## Examples

### Production Fargate Cluster

```yaml
components:
  terraform:
    ecs/production:
      vars:
        region: us-east-1
        fargate_only: true
        enable_container_insights: true
        tags:
          Environment: production
          Team: platform
          CostCenter: platform-123
```

### Development Hybrid Cluster

```yaml
components:
  terraform:
    ecs/development:
      vars:
        region: us-west-2
        fargate_only: false
        autoscaling_group_arn: ${dependency.autoscaling.outputs.autoscaling_group_arn}
        max_scaling_step_size: 2
        min_scaling_step_size: 1
        target_capacity: 70
        enable_container_insights: false
        tags:
          Environment: development
          Team: development
          CostCenter: dev-456
```

## Extending with ECS Services and Tasks

This component creates the ECS cluster infrastructure. To deploy services and tasks, you should:

1. Create the ECS cluster using this component
2. Define task definitions for your applications
3. Create ECS services that reference the cluster created by this component
4. Configure service auto-scaling, load balancers, and service discovery as needed

Example service configuration:

```yaml
components:
  terraform:
    ecs-service/web-app:
      vars:
        cluster_id: ${dependency.ecs.outputs.cluster_id}
        task_definition:
          family: "web-app"
          requires_compatibilities: ["FARGATE"]
          network_mode: "awsvpc"
          cpu: 1024
          memory: 2048
          execution_role_arn: ${dependency.iam.outputs.ecs_execution_role_arn}
          container_definitions: |
            [
              {
                "name": "web",
                "image": "${dependency.ecr.outputs.repository_url}:latest",
                "essential": true,
                "portMappings": [
                  {
                    "containerPort": 80,
                    "hostPort": 80
                  }
                ]
              }
            ]
```

## Troubleshooting

### Common Issues

1. **Missing Auto Scaling Group ARN**: When `fargate_only` is set to `false`, an Auto Scaling Group ARN must be provided.

   **Solution**: Create an Auto Scaling Group first and reference its ARN:
   ```yaml
   autoscaling_group_arn: ${dependency.autoscaling.outputs.autoscaling_group_arn}
   ```

2. **Capacity Provider Creation Failure**: Ensure the Auto Scaling Group exists and has the correct configuration.

   **Validation Command**:
   ```bash
   aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names your-asg-name
   ```

3. **Container Insights Not Showing Data**: It takes some time for metrics to appear after enabling Container Insights.

   **Solution**: Wait 5-10 minutes for data to start appearing. Verify CloudWatch Logs agent is working:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/ecs/containerinsights
   ```

4. **Cluster Not Appearing in Console**: It can take a few moments for a new cluster to appear in the AWS console.

   **Validation Command**:
   ```bash
   aws ecs list-clusters
   ```

### Validation Commands

```bash
# Validate ECS component configuration
atmos terraform validate ecs -s tenant-account-environment

# Plan ECS deployment
atmos terraform plan ecs -s tenant-account-environment

# Check ECS cluster after deployment
atmos terraform output ecs -s tenant-account-environment

# List ECS clusters in AWS account
aws ecs list-clusters --region us-west-2
```

## Related Components

- **autoscaling** - For creating Auto Scaling Groups to use with ECS
- **iam** - For creating IAM roles and policies for ECS tasks and services
- **vpc** - For networking configuration used by ECS tasks
- **securitygroup** - For setting up security groups for ECS tasks
- **alb** - For setting up load balancing for ECS services
- **ecr** - For managing container images used by ECS