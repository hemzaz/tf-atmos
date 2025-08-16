# Web Service Component

Production-ready containerized web service component with Application Load Balancer, auto-scaling, and comprehensive monitoring.

## Features

- **ECS Fargate Service**: Serverless containers with auto-scaling
- **Application Load Balancer**: HTTPS termination and health checks
- **Auto Scaling**: CPU and memory-based scaling policies
- **Security**: Security groups with least privilege access
- **Monitoring**: CloudWatch logs and Container Insights
- **Health Checks**: Application and container health monitoring
- **IAM**: Properly scoped execution and task roles

## Architecture

```
Internet → ALB → Target Group → ECS Fargate Service → CloudWatch
                                       ↓
                               Private Subnets (VPC)
```

## Usage

### Basic Configuration

```yaml
components:
  terraform:
    my-web-service:
      metadata:
        component: web-service
      vars:
        service_name: "api"
        container_image: "nginx:latest"
        container_port: 80
        vpc_id: "${atmos.component.vpc.outputs.vpc_id}"
        public_subnet_ids: "${atmos.component.vpc.outputs.public_subnet_ids}"
        private_subnet_ids: "${atmos.component.vpc.outputs.private_subnet_ids}"
```

### Production Configuration

```yaml
components:
  terraform:
    production-api:
      metadata:
        component: web-service
      vars:
        service_name: "production-api"
        container_image: "myregistry/api:v1.2.3"
        container_port: 8080
        
        # Infrastructure
        vpc_id: "${atmos.component.vpc.outputs.vpc_id}"
        public_subnet_ids: "${atmos.component.vpc.outputs.public_subnet_ids}"
        private_subnet_ids: "${atmos.component.vpc.outputs.private_subnet_ids}"
        
        # Scaling
        desired_count: 3
        task_cpu: 1024
        task_memory: 2048
        
        # Auto Scaling
        auto_scaling_enabled: true
        auto_scaling_min_capacity: 2
        auto_scaling_max_capacity: 20
        auto_scaling_cpu_target: 70.0
        auto_scaling_memory_enabled: true
        auto_scaling_memory_target: 80.0
        
        # Security
        certificate_arn: "${data.aws_ssm_parameter.certificate_arn.value}"
        allowed_cidr_blocks: ["10.0.0.0/16"]
        
        # Health Checks
        health_check_path: "/api/health"
        health_check_matcher: "200,202"
        
        # Environment Variables
        environment_variables:
          APP_ENV: "production"
          LOG_LEVEL: "info"
          
        # Secrets from Parameter Store
        secret_environment_variables:
          DATABASE_URL: "arn:aws:ssm:us-east-1:123456789012:parameter/api/database-url"
          API_KEY: "arn:aws:secretsmanager:us-east-1:123456789012:secret/api/key"
          
        # Monitoring
        container_insights_enabled: true
        log_retention_days: 30
        access_logs_enabled: true
        access_logs_bucket: "my-alb-logs-bucket"
```

### Microservices Configuration

```yaml
components:
  terraform:
    users-service:
      metadata:
        component: web-service
      vars:
        service_name: "users"
        container_image: "myregistry/users-service:latest"
        container_port: 3000
        
        # Internal service (no public ALB)
        load_balancer_enabled: false
        
        # Service mesh integration
        environment_variables:
          SERVICE_MESH_ENABLED: "true"
          JAEGER_ENDPOINT: "http://jaeger:14268"
```

## Variables

### Required

| Name | Description | Type |
|------|-------------|------|
| `service_name` | Name of the web service | `string` |
| `container_image` | Container image URI | `string` |
| `vpc_id` | VPC ID for deployment | `string` |
| `public_subnet_ids` | Public subnet IDs for ALB | `list(string)` |
| `private_subnet_ids` | Private subnet IDs for ECS | `list(string)` |

### Container Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `container_port` | Container listening port | `number` | `8080` |
| `task_cpu` | CPU units (1024 = 1 vCPU) | `number` | `512` |
| `task_memory` | Memory in MB | `number` | `1024` |
| `desired_count` | Number of tasks | `number` | `2` |

### Load Balancer

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `load_balancer_enabled` | Enable ALB | `bool` | `true` |
| `certificate_arn` | SSL certificate ARN | `string` | `""` |
| `allowed_cidr_blocks` | Allowed source CIDRs | `list(string)` | `["0.0.0.0/0"]` |

### Auto Scaling

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `auto_scaling_enabled` | Enable auto scaling | `bool` | `true` |
| `auto_scaling_min_capacity` | Minimum tasks | `number` | `2` |
| `auto_scaling_max_capacity` | Maximum tasks | `number` | `10` |
| `auto_scaling_cpu_target` | CPU utilization target | `number` | `70.0` |

### Health Checks

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `health_check_path` | Health check endpoint | `string` | `"/health"` |
| `health_check_matcher` | Success response codes | `string` | `"200"` |
| `health_check_interval` | Check interval (seconds) | `number` | `30` |

## Outputs

### Load Balancer

- `load_balancer_dns_name` - DNS name for the service
- `load_balancer_arn` - ALB ARN
- `target_group_arn` - Target group ARN

### ECS

- `cluster_name` - ECS cluster name
- `service_name` - ECS service name  
- `task_definition_arn` - Task definition ARN

### Security

- `alb_security_group_id` - ALB security group ID
- `service_security_group_id` - Service security group ID

### Computed

- `service_url` - Complete service URL
- `service_info` - Summary of service configuration

## Security Best Practices

1. **Network Isolation**: Services run in private subnets
2. **Security Groups**: Restrictive ingress rules
3. **IAM Roles**: Separate execution and task roles with minimal permissions
4. **Secrets**: Use Parameter Store or Secrets Manager for sensitive data
5. **Encryption**: HTTPS termination at load balancer
6. **Access Logs**: Optional ALB access logging

## Monitoring

- **CloudWatch Logs**: Application and container logs
- **Container Insights**: ECS performance metrics
- **Health Checks**: ALB and container health monitoring
- **Auto Scaling**: Metrics-based scaling policies

## Development Workflow

```bash
# Validate component
gaia terraform validate web-service --stack myorg-dev-testenv-01

# Plan deployment  
gaia terraform plan web-service --stack myorg-dev-testenv-01

# Deploy service
gaia terraform apply web-service --stack myorg-dev-testenv-01

# Check service status
aws ecs describe-services --cluster myorg-testenv-01-api-cluster --services myorg-testenv-01-api-service

# View logs
aws logs tail /ecs/myorg-testenv-01-api --follow
```

## Troubleshooting

### Service Won't Start

1. Check CloudWatch logs: `/ecs/{service-name}`
2. Verify container image exists and is accessible
3. Check security group rules
4. Validate environment variables and secrets

### Health Check Failures

1. Verify health check endpoint returns 200
2. Check container port configuration
3. Ensure health check path is correct
4. Review security group rules

### Auto Scaling Issues

1. Check CloudWatch metrics for CPU/memory usage
2. Verify scaling policies are configured
3. Check service capacity constraints
4. Review scaling cooldown periods

## Related Components

- **VPC**: Provides network infrastructure
- **Certificate Manager**: SSL/TLS certificates
- **Secrets Manager**: Secure credential storage
- **Parameter Store**: Configuration management

---

**Built for production workloads with security, scalability, and observability in mind.**