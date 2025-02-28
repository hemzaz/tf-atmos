# AWS CloudWatch Monitoring Component

_Last Updated: February 28, 2025_

## Overview

This component creates and manages AWS CloudWatch resources for comprehensive monitoring, including dashboards, alarms, log groups, metric filters, and certificate monitoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  CloudWatch Monitoring                      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌─────────────────┐     ┌─────────────────┐                │
│  │                 │     │                 │                │
│  │   Dashboards    │     │     Alarms      │                │
│  │                 │     │                 │                │
│  └────────┬────────┘     └────────┬────────┘                │
│           │                       │                         │
│           ▼                       ▼                         │
│  ┌─────────────────┐     ┌─────────────────┐                │
│  │  • System       │     │  • CPU          │     ┌─────┐    │
│  │  • Certificate  │     │  • Memory       │     │     │    │
│  │  • Custom       │     │  • DB Conn      │────►│ SNS │    │
│  │                 │     │  • Lambda Error │     │     │    │
│  └─────────────────┘     │  • Certificate  │     └──┬──┘    │
│                          └─────────────────┘        │       │
│                                                     │       │
│                                                     ▼       │
│                                           ┌──────────────┐  │
│                                           │ Notification │  │
│                                           │ Subscribers  │  │
│                                           └──────────────┘  │
│                                                             │
│  ┌─────────────────┐     ┌─────────────────┐                │
│  │                 │     │                 │                │
│  │   Log Groups    │────►│ Metric Filters  │                │
│  │                 │     │                 │                │
│  └─────────────────┘     └────────┬────────┘                │
│                                   │                         │
│                                   ▼                         │
│                          ┌─────────────────┐                │
│                          │  Custom Metrics │                │
│                          │  and Alarms     │                │
│                          └─────────────────┘                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **CloudWatch Dashboards**: Create customizable dashboards for system and certificate monitoring
- **Multi-Resource Alarms**: Create alarms for EC2, RDS, Lambda, ECS, and other AWS resources
- **Log Management**: Establish log groups with retention policies and metric filters
- **Certificate Monitoring**: Track SSL/TLS certificate expiration and status
- **Notification System**: Configure SNS topics and subscriptions for alarm notifications
- **Custom Metrics**: Extract and analyze custom metrics from log data

## Usage

### Basic Monitoring Configuration

```yaml
components:
  terraform:
    monitoring:
      vars:
        region: us-west-2
        
        # Basic configuration
        create_dashboard: true
        create_sns_topic: true
        alarm_email_subscriptions:
          - "alerts@example.com"
        
        # Resources to monitor
        vpc_id: ${dependency.vpc.outputs.vpc_id}
        rds_instances:
          - ${dependency.rds.outputs.db_instance_id}
        lambda_functions:
          - ${dependency.lambda.outputs.function_name}
        
        # Log groups
        log_groups:
          application:
            retention_days: 30
          security:
            retention_days: 90
        
        # Tags
        tags:
          Environment: dev
          Name: monitoring
```

### Complete Production Monitoring

```yaml
components:
  terraform:
    monitoring:
      vars:
        region: us-west-2
        
        # Dashboard
        create_dashboard: true
        vpc_id: ${dependency.vpc.outputs.vpc_id}
        rds_instances:
          - ${dependency.rds.outputs.db_instance_id}
        ecs_clusters:
          - ${dependency.ecs.outputs.cluster_name}
        lambda_functions:
          - ${dependency.lambda.outputs.function_name}
        load_balancers:
          - ${dependency.alb.outputs.lb_id}
        elasticache_clusters:
          - ${dependency.elasticache.outputs.cluster_id}
        
        # Notifications
        create_sns_topic: true
        alarm_email_subscriptions:
          - "oncall@example.com"
          - "devops@example.com"
        
        # CPU Alarms
        cpu_alarms:
          ec2_instance:
            namespace: "AWS/EC2"
            evaluation_periods: 2
            period: 300
            threshold: 80
            dimensions:
              InstanceId: ${dependency.ec2.outputs.instance_id}
          
          ecs_service:
            namespace: "AWS/ECS"
            evaluation_periods: 2
            period: 300
            threshold: 75
            dimensions:
              ClusterName: ${dependency.ecs.outputs.cluster_name}
              ServiceName: ${dependency.ecs.outputs.service_name}
        
        # Memory Alarms
        memory_alarms:
          ecs_service:
            namespace: "AWS/ECS"
            evaluation_periods: 2
            period: 300
            threshold: 80
            dimensions:
              ClusterName: ${dependency.ecs.outputs.cluster_name}
              ServiceName: ${dependency.ecs.outputs.service_name}
        
        # DB Connection Alarms
        db_connection_alarms:
          ${dependency.rds.outputs.db_instance_id}:
            evaluation_periods: 3
            period: 300
            threshold: 80
        
        # Lambda Error Alarms
        lambda_error_alarms:
          ${dependency.lambda.outputs.function_name}:
            evaluation_periods: 1
            period: 60
            threshold: 1
        
        # Log Groups and Metric Filters
        log_groups:
          application:
            retention_days: 30
          api:
            retention_days: 90
          database:
            retention_days: 90
        
        log_metric_filters:
          api_error:
            log_group_name: "api"
            pattern: "ERROR"
            evaluation_periods: 1
            period: 60
            threshold: 5
          security_alert:
            log_group_name: "security"
            pattern: "ALERT"
            evaluation_periods: 1
            period: 60
            threshold: 1
        
        # Certificate Monitoring
        enable_certificate_monitoring: true
        eks_cluster_name: ${dependency.eks.outputs.cluster_name}
        certificate_arns:
          - ${dependency.acm.outputs.certificate_arn}
        certificate_names:
          - "example.com"
        certificate_domains:
          - "example.com"
        certificate_statuses:
          - "ISSUED"
        certificate_expiry_dates:
          - "2025-01-01"
        certificate_expiry_threshold: 30
        
        # Tags
        tags:
          Environment: production
          Name: monitoring
          Project: core-infrastructure
          Owner: devops
          ManagedBy: atmos
```

### Certificate Monitoring Dashboard

```yaml
components:
  terraform:
    monitoring/certificates:
      vars:
        region: us-west-2
        
        # Enable certificate monitoring
        enable_certificate_monitoring: true
        eks_cluster_name: ${dependency.eks.outputs.cluster_name}
        
        # Certificate details
        certificate_arns:
          - ${dependency.acm.outputs.api_certificate_arn}
          - ${dependency.acm.outputs.website_certificate_arn}
        certificate_names:
          - "api.example.com"
          - "www.example.com"
        certificate_domains:
          - "api.example.com"
          - "www.example.com"
        certificate_statuses:
          - "ISSUED" 
          - "ISSUED"
        certificate_expiry_dates:
          - "2024-06-01"
          - "2024-08-15"
        certificate_expiry_threshold: 45
        
        # Notifications
        create_sns_topic: true
        alarm_email_subscriptions:
          - "security@example.com"
        
        # Tags
        tags:
          Environment: production
          Name: certificate-monitoring
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| log_groups | Map of log groups to create | `map(object({ retention_days = number }))` | `{}` | no |
| kms_key_id | KMS key ID for log encryption | `string` | `null` | no |
| create_dashboard | Whether to create CloudWatch dashboard | `bool` | `false` | no |
| vpc_id | VPC ID for dashboard metrics | `string` | `""` | no |
| rds_instances | List of RDS instances to monitor | `list(string)` | `[]` | no |
| ecs_clusters | List of ECS clusters to monitor | `list(string)` | `[]` | no |
| lambda_functions | List of Lambda functions to monitor | `list(string)` | `[]` | no |
| load_balancers | List of load balancers to monitor | `list(string)` | `[]` | no |
| elasticache_clusters | List of ElastiCache clusters to monitor | `list(string)` | `[]` | no |
| create_sns_topic | Whether to create an SNS topic for alarms | `bool` | `true` | no |
| alarm_email_subscriptions | List of email addresses to notify for alarms | `list(string)` | `[]` | no |
| cpu_alarms | Map of CPU alarms to create | `map(object)` | `{}` | no |
| memory_alarms | Map of memory alarms to create | `map(object)` | `{}` | no |
| db_connection_alarms | Map of database connection alarms to create | `map(object)` | `{}` | no |
| lambda_error_alarms | Map of Lambda error alarms to create | `map(object)` | `{}` | no |
| log_metric_filters | Map of log metric filters to create | `map(object)` | `{}` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |
| enable_certificate_monitoring | Whether to enable certificate monitoring dashboard and alarms | `bool` | `false` | no |
| eks_cluster_name | EKS cluster name for certificate management monitoring | `string` | `""` | no |
| certificate_arns | List of certificate ARNs to monitor | `list(string)` | `[]` | no |
| certificate_names | List of certificate names corresponding to the ARNs | `list(string)` | `[]` | no |
| certificate_domains | List of certificate domain names | `list(string)` | `[]` | no |
| certificate_statuses | List of certificate statuses | `list(string)` | `[]` | no |
| certificate_expiry_dates | List of certificate expiry dates in human-readable format | `list(string)` | `[]` | no |
| certificate_alarm_arns | List of certificate alarm ARNs to display in dashboard | `list(string)` | `[]` | no |
| certificate_expiry_threshold | Threshold in days for certificate expiry alarms | `number` | `30` | no |

## Outputs

| Name | Description |
|------|-------------|
| log_group_names | Map of log group names |
| log_group_arns | Map of log group ARNs |
| dashboard_name | Name of the CloudWatch dashboard |
| sns_topic_arn | ARN of the SNS topic for alarms |
| cpu_alarm_names | Map of CPU alarm names |
| memory_alarm_names | Map of memory alarm names |
| db_connection_alarm_names | Map of database connection alarm names |
| lambda_error_alarm_names | Map of Lambda error alarm names |

## Best Practices

### Dashboard Design

- Group related metrics together for better visualization
- Use the template files for consistent dashboard layouts
- Include both high-level overviews and detailed metrics when needed
- Use appropriate visualization types (time series, single value, bar charts) for different metrics
- Consider using dashboard variables for dynamic filtering when applicable

### Alarm Configuration

- Set appropriate thresholds based on baseline metrics for your workloads
- Use multiple evaluation periods to avoid false positives from transient spikes
- Configure different severity levels for critical resources
- Include clear alarm descriptions that provide context and troubleshooting guidance
- Test alarms by manually triggering them or simulating conditions

### Log Management

- Set appropriate retention periods based on regulatory requirements and cost considerations
- Create metric filters that extract actionable insights from your logs
- Standardize log formats across applications to simplify metric extraction
- Consider using CloudWatch Logs Insights for ad-hoc query and analysis
- Monitor log storage usage to avoid unexpected costs

### Certificate Management

- Set appropriate expiry thresholds (30+ days) to provide sufficient time for renewal
- Use different threshold levels (warning, critical) for graduated alerts
- Include certificate details in dashboard for easy reference
- Integrate with existing certificate management workflows
- Implement automated certificate renewal where possible

## Troubleshooting

### Common Issues

#### Dashboard Not Showing Data

- Verify IAM permissions for the CloudWatch service
- Check if the resources being monitored exist and are correctly specified
- Ensure the region is correctly specified and matches the resources
- Verify the time range in the dashboard view is appropriate for the data

#### Alarms Not Triggering

- Verify the SNS topic exists and has correct access policies
- Check if alarm actions are enabled (`actions_enabled = true`)
- Confirm the metric being monitored is emitting data
- Verify the threshold and evaluation periods are appropriate
- Test the SNS subscription with a test message

#### Log Group Issues

- Check IAM permissions for creating and managing log groups
- Verify KMS key permissions if using encrypted logs
- Ensure log retention policies comply with organization requirements
- Review metric filter patterns for accuracy

#### Missing Certificate Data

- Verify the certificate ARNs are valid and accessible
- Check if the certificates exist in the specified region
- Ensure the EKS cluster has External Secrets configured for certificate monitoring
- Verify CloudWatch permissions to access certificate metrics

### CloudWatch Logs Insights Queries

#### Finding Error Patterns

```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

#### Analyzing API Response Times

```
fields @timestamp, @message
| parse @message "responseTime: * ms" as responseTime
| stats avg(responseTime) as avgResponseTime by bin(5m)
| sort avgResponseTime desc
```

#### Identifying Authentication Failures

```
fields @timestamp, @message
| filter @message like /Authentication failure/ or @message like /access denied/
| stats count() as authFailures by bin(1h)
| sort authFailures desc
```

## Related Resources

- [AWS CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html)
- [CloudWatch Logs Insights Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [CloudWatch Dashboard JSON Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/CloudWatch-Dashboard-Body-Structure.html)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
- [External Secrets Operator Documentation](https://external-secrets.io/latest/)

## Security Considerations

- Ensure that sensitive log data is encrypted with KMS
- Implement appropriate IAM policies for CloudWatch access
- Limit access to alarm actions to prevent unauthorized changes
- Consider using AWS organizations for centralized monitoring across accounts
- Use encrypted SNS topics for sensitive notifications
- Implement CloudWatch Logs Insights with appropriate permissions