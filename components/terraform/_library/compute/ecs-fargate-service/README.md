# ECS Fargate Service Module

Production-ready ECS Fargate service with auto-scaling, blue-green deployments, circuit breaker, and cost optimization.

## Features

- **Complete ECS Fargate Service**: Cluster, service, task definition with full configuration
- **Auto-Scaling**: CPU, memory, and ALB request count-based scaling
- **Blue/Green Deployments**: CodeDeploy integration for zero-downtime deployments
- **Circuit Breaker**: Automatic rollback on failed deployments
- **Service Discovery**: AWS Cloud Map integration for internal service communication
- **Load Balancer**: ALB/NLB integration with health checks
- **Monitoring**: CloudWatch Container Insights, logs, and X-Ray tracing
- **Security**: Least privilege IAM roles, security groups, Secrets Manager integration
- **Cost Optimization**: Fargate Spot support, capacity provider strategy
- **High Availability**: Multi-AZ deployment with configurable redundancy
- **EFS Support**: Persistent storage with EFS volume integration
- **ECS Exec**: Debug running containers with interactive shell access

## Architecture Patterns

### 1. Standard Fargate Service (Recommended)
```
ALB → Target Group → ECS Service (Fargate) → Tasks
                         ↓
                    Auto-Scaling (CPU/Memory)
                         ↓
                    CloudWatch Logs
```

### 2. Blue/Green Deployment
```
ALB → [Blue Target Group] → Blue Task Set
      [Green Target Group] → Green Task Set
              ↓
        CodeDeploy manages traffic shift
```

### 3. Service Mesh Integration
```
ECS Service → Service Discovery → Cloud Map
                                     ↓
                             Internal DNS (service.local)
```

## Usage

### Basic Example

```hcl
module "ecs_service" {
  source = "../../_library/compute/ecs-fargate-service"

  name_prefix = "myapp"
  environment = "production"
  service_name = "api"

  # Networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Task configuration
  cpu    = 512
  memory = 1024

  container_definitions = [
    {
      name      = "app"
      image     = "nginx:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/myapp/api"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ]

  # Load balancer
  enable_load_balancer = true
  target_group_arn     = aws_lb_target_group.app.arn
  container_name       = "app"
  container_port       = 8080

  # Auto-scaling
  enable_autoscaling       = true
  autoscaling_min_capacity = 2
  autoscaling_max_capacity = 10
  cpu_target_value         = 70
  memory_target_value      = 80

  tags = {
    Project = "MyApp"
  }
}
```

### Complete Example with All Features

See [examples/complete](./examples/complete) for a full-featured implementation including:
- Blue/green deployments
- Service discovery
- Secrets management
- EFS volumes
- Fargate Spot
- Custom IAM policies

### Blue/Green Deployment Example

See [examples/blue-green](./examples/blue-green) for CodeDeploy integration.

## Cost Comparison

| Configuration | Monthly Cost (USD) | Use Case |
|--------------|-------------------|----------|
| 0.25 vCPU, 0.5 GB (2 tasks) | ~$26 | Development |
| 0.5 vCPU, 1 GB (3 tasks) | ~$78 | Small production |
| 1 vCPU, 2 GB (5 tasks) | ~$260 | Medium production |
| 2 vCPU, 4 GB (10 tasks) | ~$1,040 | Large production |

**Cost Optimization:**
- Enable Fargate Spot for 50-70% savings on interruptible workloads
- Use auto-scaling to scale down during off-peak hours
- Right-size CPU and memory based on actual usage

Pricing based on us-east-1 region, 730 hours/month. Add ALB costs (~$16/month + data transfer).

## Auto-Scaling Strategies

### CPU-Based Scaling (Default)
```hcl
cpu_target_value = 70  # Scale when CPU > 70%
```

### Memory-Based Scaling
```hcl
memory_target_value = 80  # Scale when memory > 80%
```

### ALB Request Count Scaling
```hcl
enable_alb_target_tracking = true
alb_target_value = 1000  # Requests per target per minute
```

### Combined Approach (Recommended for Production)
Enable all three metrics. ECS will scale based on whichever metric breaches first.

## Deployment Strategies

### Rolling Update (Default)
- **Strategy**: ECS native rolling updates
- **Downtime**: Zero downtime
- **Rollback**: Manual or circuit breaker
- **Speed**: Fast (2-5 minutes)
- **Best for**: Most applications

```hcl
deployment_maximum_percent         = 200
deployment_minimum_healthy_percent = 100
enable_deployment_circuit_breaker  = true
```

### Blue/Green Deployment
- **Strategy**: CodeDeploy traffic shifting
- **Downtime**: Zero downtime
- **Rollback**: Automatic
- **Speed**: Slower (5-15 minutes)
- **Best for**: Critical production services

```hcl
enable_blue_green_deployment = true
deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"
termination_wait_time = 5
```

## Security Best Practices

1. **Always use private subnets** for tasks (default)
2. **Enable secrets management** for sensitive data
3. **Use least privilege IAM roles** (auto-created by default)
4. **Enable Container Insights** for security monitoring
5. **Use VPC endpoints** to avoid internet traffic for AWS services
6. **Enable encryption** for logs and EFS volumes
7. **Scan container images** before deployment (not included in module)

## Performance Considerations

### Task Sizing Guidelines

| vCPU | Memory | Concurrent Requests | Use Case |
|------|--------|---------------------|----------|
| 0.25 | 0.5-2 GB | <100 | Lightweight APIs |
| 0.5 | 1-4 GB | 100-500 | Standard web apps |
| 1 | 2-8 GB | 500-2000 | Medium workloads |
| 2 | 4-16 GB | 2000-5000 | Heavy processing |
| 4+ | 8-30 GB | 5000+ | Data processing |

### Health Check Configuration

```hcl
health_check_grace_period_seconds = 60  # Adjust based on startup time
```

- Short grace period (30-60s): Fast-starting apps
- Medium grace period (60-120s): Database migrations
- Long grace period (120-300s): Model loading, cache warming

## Monitoring and Observability

### CloudWatch Metrics (Automatic)
- `CPUUtilization`
- `MemoryUtilization`
- `TargetResponseTime` (with ALB)
- `HealthyHostCount`
- `RunningTaskCount`

### Container Insights (Optional)
```hcl
enable_container_insights = true
```

Provides:
- Per-container CPU/memory metrics
- Network metrics
- Task-level performance data

### X-Ray Tracing (Optional)
```hcl
enable_xray_tracing = true
```

Requires X-Ray daemon sidecar in your task definition.

## Troubleshooting

### Tasks Fail to Start

**Symptoms**: Tasks stuck in PENDING or immediately fail

**Common Causes**:
1. Insufficient permissions in execution role
2. Image pull authentication issues
3. Invalid container definitions
4. Insufficient capacity in subnets

**Solution**: Check CloudWatch Logs and ECS events

### Service Not Scaling

**Symptoms**: Service stays at desired count despite high CPU/memory

**Common Causes**:
1. Auto-scaling not enabled
2. Max capacity reached
3. Cooldown period active
4. CloudWatch alarms not triggering

**Solution**: Verify autoscaling configuration and CloudWatch metrics

### High Costs

**Symptoms**: ECS costs higher than expected

**Solutions**:
1. Enable Fargate Spot: `enable_fargate_spot = true`
2. Right-size tasks: Reduce CPU/memory if underutilized
3. Scale down during off-peak: Adjust `autoscaling_min_capacity`
4. Use scheduled scaling for predictable traffic patterns

## Migration Guide

### From EC2 Launch Type
1. Remove EC2-specific configurations (AMI, instance type)
2. Switch to Fargate-compatible task definition
3. Update network mode to `awsvpc`
4. Adjust CPU/memory to Fargate-supported values
5. Update IAM roles (execution vs task role)

### From Other Container Orchestrators
1. Convert container definitions to ECS format
2. Map environment variables and secrets
3. Configure health checks
4. Set up service discovery (if needed)
5. Migrate volumes to EFS (if persistent storage needed)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Name prefix for resources | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| service_name | Name of the ECS service | `string` | n/a | yes |
| vpc_id | ID of the VPC | `string` | n/a | yes |
| subnet_ids | List of subnet IDs | `list(string)` | n/a | yes |
| container_definitions | Container definitions | `any` | n/a | yes |
| cpu | CPU units | `number` | `256` | no |
| memory | Memory in MB | `number` | `512` | no |
| desired_count | Desired task count | `number` | `2` | no |
| enable_autoscaling | Enable auto-scaling | `bool` | `true` | no |
| enable_load_balancer | Enable load balancer | `bool` | `true` | no |
| target_group_arn | Target group ARN | `string` | `null` | no |

For complete variable list, see [variables.tf](./variables.tf)

## Outputs

| Name | Description |
|------|-------------|
| service_id | ID of the ECS service |
| service_arn | ARN of the ECS service |
| cluster_name | Name of the ECS cluster |
| task_definition_arn | ARN of the task definition |
| security_group_id | ID of the security group |
| log_group_name | Name of the CloudWatch Log Group |

For complete output list, see [outputs.tf](./outputs.tf)

## Examples

- [Basic](./examples/basic) - Simple Fargate service
- [Complete](./examples/complete) - All features enabled
- [Blue-Green](./examples/blue-green) - CodeDeploy integration

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0, < 6.0.0 |

## License

See [LICENSE](../../LICENSE)

## Maintainers

- **Platform Engineering Team** (platform-team@example.com)
- Support: #platform-support

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history.
