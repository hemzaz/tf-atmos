# ASG Launch Template Module

Production-ready EC2 Auto Scaling with launch template, mixed instances, multiple scaling policies, and cost optimization.

## Features

- **Launch Template**: Modern launch template with IMDSv2, encrypted EBS, monitoring
- **Mixed Instances**: Multiple instance types with Spot/On-Demand mix
- **Auto-Scaling**: CPU, memory, ALB request count, scheduled scaling
- **Cost Optimization**: Spot instances, instance type diversification, warm pools
- **High Availability**: Multi-AZ deployment, instance refresh, health checks
- **Monitoring**: CloudWatch agent, detailed monitoring, custom metrics, alarms
- **Security**: IMDSv2, encrypted volumes, IAM roles, security groups

## Quick Start

```hcl
module "asg" {
  source = "../../_library/compute/asg-launch-template"

  name_prefix = "myapp"
  environment = "production"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  # Instance configuration
  instance_type  = "t3.medium"
  instance_types = ["t3.medium", "t3a.medium", "t2.medium"]

  # Mixed instances for cost optimization
  enable_mixed_instances               = true
  on_demand_base_capacity             = 0
  on_demand_percentage_above_base     = 20
  spot_allocation_strategy            = "capacity-optimized"

  # Capacity
  min_size         = 2
  max_size         = 10
  desired_capacity = 3

  # Auto-scaling
  enable_target_tracking_cpu = true
  cpu_target_value           = 70

  # Instance refresh
  enable_instance_refresh = true

  tags = {
    Project = "MyApp"
  }
}
```

## Cost Comparison

| Configuration | Monthly Cost | Savings vs On-Demand |
|--------------|--------------|----------------------|
| 3x t3.medium On-Demand | $100.80 | 0% |
| 3x t3.medium 50% Spot | $55.44 | 45% |
| 3x t3.medium 80% Spot | $33.26 | 67% |
| Mixed types 80% Spot | $25-35 | 65-75% |

**Recommendations:**
- Use 70-80% Spot for non-critical workloads
- Use `capacity-optimized` allocation strategy
- Enable warm pools for faster scaling
- Use multiple instance types for better Spot availability

## License

See [LICENSE](../../LICENSE)
