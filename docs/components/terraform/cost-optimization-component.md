# Cost Optimization Module

## Overview

The Cost Optimization module provides automated infrastructure cost management capabilities for AWS environments. It implements industry best practices for FinOps, including automated resource scheduling, unused resource cleanup, cost anomaly detection, and savings recommendations.

## Features

### 1. Automated Instance Scheduling
- **Auto Start/Stop**: Automatically starts and stops EC2 instances and RDS databases based on schedules
- **Environment-Aware**: Different schedules for dev, staging, and production
- **Weekend Shutdown**: Optional weekend shutdown for non-production resources
- **Business Hours**: Configurable business hours for resource availability

### 2. Cost Monitoring & Alerts
- **Budget Alerts**: Configurable monthly budgets with threshold notifications
- **Anomaly Detection**: Automatic detection of unusual spending patterns
- **Real-time Dashboard**: CloudWatch dashboard for cost visualization
- **Email Notifications**: SNS-based alerting for cost events

### 3. Resource Cleanup
- **Unused Volumes**: Identifies and removes unattached EBS volumes
- **Old Snapshots**: Cleans up snapshots older than retention period
- **Elastic IPs**: Releases unassociated Elastic IPs
- **Dry Run Mode**: Safe testing before actual deletion

### 4. Optimization Recommendations
- **Savings Plans**: Weekly analysis of Savings Plans opportunities
- **Reserved Instances**: Recommendations for RI purchases
- **Right-sizing**: Identifies over-provisioned resources
- **Spot Instances**: Suggests spot instance usage patterns

## Usage

### Basic Configuration

```hcl
module "cost_optimization" {
  source = "./components/terraform/cost-optimization"
  
  namespace   = "mycompany"
  environment = "dev"
  stage       = "main"
  region      = "us-west-2"
  
  # Budget configuration
  monthly_budget_limit           = "5000"
  budget_notification_emails     = ["finance@mycompany.com"]
  cost_anomaly_notification_email = "ops@mycompany.com"
  
  # Cleanup settings
  cleanup_dry_run        = "false"  # Set to "true" for testing
  cleanup_unused_volumes = true
  cleanup_old_snapshots  = true
  snapshot_retention_days = 30
  
  # Auto-scaling thresholds
  scale_down_threshold = 20
  scale_up_threshold   = 70
  
  # Business hours (for auto-shutdown)
  business_hours_start = "07:00"
  business_hours_end   = "19:00"
  weekend_shutdown     = true
  
  tags = {
    Team       = "Platform"
    CostCenter = "Engineering"
  }
}
```

### Environment-Specific Settings

The module automatically applies different optimization strategies based on the environment:

#### Development Environment
- **Auto-shutdown**: Enabled (nights and weekends)
- **Spot instances**: 70% of capacity
- **Schedule**: Mon-Fri 7 AM - 7 PM
- **Reserved Instances**: Disabled
- **Savings Plans**: Disabled

#### Staging Environment
- **Auto-shutdown**: Enabled (nights and weekends)
- **Spot instances**: 50% of capacity
- **Schedule**: Mon-Fri 6 AM - 8 PM
- **Reserved Instances**: Disabled
- **Savings Plans**: Enabled

#### Production Environment
- **Auto-shutdown**: Disabled (24/7 availability)
- **Spot instances**: 20% of capacity (for fault-tolerant workloads)
- **Schedule**: Always on
- **Reserved Instances**: Enabled
- **Savings Plans**: Enabled

## Cost Savings Estimates

Based on typical usage patterns, this module can achieve:

| Optimization Type | Potential Savings | Implementation Time |
|------------------|-------------------|-------------------|
| Auto-shutdown (Dev/Staging) | 30-40% | Immediate |
| Spot Instances | 50-70% | 1-2 weeks |
| Reserved Instances | 30-50% | 2-4 weeks |
| Savings Plans | 20-30% | 2-4 weeks |
| Unused Resource Cleanup | 5-10% | Immediate |
| S3 Lifecycle Policies | 10-20% | Immediate |

## Lambda Functions

### Instance Scheduler
Manages the start/stop of EC2 instances and RDS databases based on tags and schedules.

**Tags Required**:
- `Environment`: Must match the module's environment
- `AutoShutdown`: Set to "true" to enable scheduling

### Savings Analyzer
Runs weekly to analyze cost optimization opportunities and sends recommendations.

### Resource Cleanup
Identifies and removes unused resources to reduce costs.

## Monitoring

### CloudWatch Dashboard
Access the cost optimization dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards:name=<namespace>-<environment>-<stage>-cost-optimization
```

### Metrics Tracked
- Estimated monthly charges
- EC2 CPU utilization
- RDS utilization
- Spot instance usage
- Reserved instance coverage
- Savings realized

## Best Practices

### 1. Tagging Strategy
Ensure all resources are properly tagged:
```hcl
tags = {
  Environment  = "dev"
  Team        = "platform"
  CostCenter  = "engineering"
  Project     = "infrastructure"
  AutoShutdown = "true"  # For scheduled resources
}
```

### 2. Progressive Implementation
1. Start with dry-run mode for cleanup operations
2. Implement auto-shutdown in development first
3. Gradually increase spot instance percentage
4. Purchase Reserved Instances after analyzing usage patterns

### 3. Regular Reviews
- Weekly: Review savings analyzer recommendations
- Monthly: Analyze budget vs actual spending
- Quarterly: Reassess Reserved Instance and Savings Plans

## Troubleshooting

### Issue: Resources not shutting down
**Solution**: Check that resources have the correct tags:
```bash
aws ec2 describe-tags --filters "Name=resource-id,Values=i-xxxxx"
```

### Issue: Budget alerts not received
**Solution**: Verify SNS subscription confirmation:
```bash
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
```

### Issue: Cleanup function not working
**Solution**: Check Lambda logs:
```bash
aws logs tail /aws/lambda/<function-name> --follow
```

## Security Considerations

### IAM Permissions
The module creates IAM roles with least-privilege policies:
- **Scheduler Role**: EC2/RDS start/stop permissions
- **Analyzer Role**: Read-only Cost Explorer access
- **Cleanup Role**: Delete permissions with tag-based conditions

### Data Protection
- No sensitive data is stored in Lambda environment variables
- All notifications use encrypted SNS topics
- CloudWatch Logs are encrypted at rest

## Integration with Atmos

### Stack Configuration
```yaml
# stacks/catalog/cost-optimization/defaults.yaml
components:
  terraform:
    cost-optimization:
      vars:
        namespace: fnx
        monthly_budget_limit: "10000"
        cost_anomaly_notification_email: "platform@company.com"
        budget_notification_emails:
          - "finance@company.com"
          - "platform@company.com"
        cleanup_dry_run: "false"
        enable_spot_instances: true
        enable_reserved_instances: false
        enable_savings_plans: false
```

### Workflow Integration
```yaml
# workflows/cost-optimization.yaml
workflows:
  cost-report:
    description: Generate cost optimization report
    steps:
      - command: terraform output -json
        component: cost-optimization
      - command: python scripts/generate_cost_report.py
```

## Outputs

| Output | Description |
|--------|-------------|
| `instance_scheduler_function_arn` | ARN of the scheduler Lambda |
| `savings_analyzer_function_arn` | ARN of the analyzer Lambda |
| `cost_alerts_topic_arn` | SNS topic for cost alerts |
| `cost_dashboard_url` | Direct link to CloudWatch dashboard |
| `optimization_settings` | Current optimization configuration |
| `estimated_monthly_savings` | Projected savings from current settings |

## Contributing

When modifying this module:
1. Update the README with new features
2. Add appropriate variable validations
3. Include cost impact estimates
4. Test in development environment first
5. Document any new IAM permissions required

## License

This module is part of the internal infrastructure toolkit and follows company licensing policies.