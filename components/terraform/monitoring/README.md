# Monitoring Component

This component creates and manages AWS CloudWatch resources for monitoring, including dashboards, alarms, log groups, and metric filters.

## Features

- Create and manage CloudWatch dashboards
- Define comprehensive alarm sets for common AWS services
- Create CloudWatch log groups with retention policies
- Configure metric filters for log pattern alerting
- Set up composite alarms for complex conditions
- Configure SNS topics for alarm notifications
- Support for anomaly detection alarms
- Define custom metrics and dimensions

## Usage

```hcl
module "monitoring" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/monitoring"
  
  region = var.region
  
  # CloudWatch Dashboard
  create_dashboard = true
  dashboard_name   = "system-overview"
  dashboard_body   = templatefile("./templates/dashboard.json.tpl", {
    region      = var.region
    instance_id = module.ec2.instance_id
    rds_id      = module.rds.db_instance_id
  })
  
  # SNS Topic for Alerts
  create_sns_topic = true
  sns_topic_name   = "monitoring-alerts"
  sns_subscriptions = [
    {
      protocol = "email"
      endpoint = "alerts@example.com"
    },
    {
      protocol = "https"
      endpoint = "https://api.pagerduty.com/integration/abc123"
    }
  ]
  
  # EC2 Alarms
  ec2_alarms = {
    cpu_high = {
      instance_id         = module.ec2.instance_id
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 2
      metric_name         = "CPUUtilization"
      namespace           = "AWS/EC2"
      period              = 300
      statistic           = "Average"
      threshold           = 80
      alarm_description   = "EC2 CPU utilization is too high"
      alarm_actions       = ["${module.monitoring.sns_topic_arn}"]
    }
  }
  
  # RDS Alarms
  rds_alarms = {
    high_cpu = {
      db_instance_identifier = module.rds.db_instance_id
      comparison_operator    = "GreaterThanThreshold"
      evaluation_periods     = 2
      metric_name            = "CPUUtilization"
      namespace              = "AWS/RDS"
      period                 = 300
      statistic              = "Average"
      threshold              = 80
      alarm_description      = "RDS CPU utilization is too high"
      alarm_actions          = ["${module.monitoring.sns_topic_arn}"]
    },
    storage_low = {
      db_instance_identifier = module.rds.db_instance_id
      comparison_operator    = "LessThanThreshold"
      evaluation_periods     = 1
      metric_name            = "FreeStorageSpace"
      namespace              = "AWS/RDS"
      period                 = 300
      statistic              = "Average"
      threshold              = 10737418240  # 10 GB in bytes
      alarm_description      = "RDS free storage space is too low"
      alarm_actions          = ["${module.monitoring.sns_topic_arn}"]
    }
  }
  
  # Lambda Alarms
  lambda_alarms = {
    errors = {
      function_name       = module.lambda.function_name
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "Errors"
      namespace           = "AWS/Lambda"
      period              = 300
      statistic           = "Sum"
      threshold           = 1
      alarm_description   = "Lambda function has errors"
      alarm_actions       = ["${module.monitoring.sns_topic_arn}"]
    }
  }
  
  # CloudWatch Log Groups
  log_groups = {
    application = {
      name              = "/app/production"
      retention_in_days = 90
      metric_filters = [
        {
          name           = "ErrorFilter"
          pattern        = "ERROR"
          metric_name    = "ApplicationErrors"
          metric_namespace = "CustomMetrics"
          metric_value   = "1"
          default_value  = "0"
        }
      ]
    }
  }
  
  # Composite Alarms
  composite_alarms = {
    system_critical = {
      alarm_name        = "SystemCriticalState"
      alarm_description = "Multiple critical alarms are in ALARM state"
      alarm_rule        = "ALARM(${aws_cloudwatch_metric_alarm.ec2_alarms.cpu_high.alarm_name}) AND (ALARM(${aws_cloudwatch_metric_alarm.rds_alarms.high_cpu.alarm_name}) OR ALARM(${aws_cloudwatch_metric_alarm.lambda_alarms.errors.alarm_name}))"
      alarm_actions     = ["${module.monitoring.sns_topic_arn}"]
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
| create_dashboard | Whether to create a CloudWatch dashboard | `bool` | `false` | no |
| dashboard_name | Name of the CloudWatch dashboard | `string` | `"system-overview"` | no |
| dashboard_body | JSON body of the CloudWatch dashboard | `string` | `null` | no |
| create_sns_topic | Whether to create an SNS topic for alarms | `bool` | `false` | no |
| sns_topic_name | Name of the SNS topic | `string` | `"monitoring-alerts"` | no |
| sns_subscriptions | List of SNS subscriptions | `list(map(string))` | `[]` | no |
| ec2_alarms | Map of EC2 alarms to create | `map(any)` | `{}` | no |
| rds_alarms | Map of RDS alarms to create | `map(any)` | `{}` | no |
| lambda_alarms | Map of Lambda alarms to create | `map(any)` | `{}` | no |
| api_gateway_alarms | Map of API Gateway alarms to create | `map(any)` | `{}` | no |
| elb_alarms | Map of ELB alarms to create | `map(any)` | `{}` | no |
| log_groups | Map of CloudWatch log groups to create | `map(any)` | `{}` | no |
| composite_alarms | Map of composite alarms to create | `map(any)` | `{}` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| dashboard_arn | ARN of the CloudWatch dashboard |
| sns_topic_arn | ARN of the SNS topic for alarms |
| ec2_alarms | Map of EC2 alarm names to their ARNs |
| rds_alarms | Map of RDS alarm names to their ARNs |
| lambda_alarms | Map of Lambda alarm names to their ARNs |
| api_gateway_alarms | Map of API Gateway alarm names to their ARNs |
| elb_alarms | Map of ELB alarm names to their ARNs |
| log_group_arns | Map of CloudWatch log group names to their ARNs |
| composite_alarm_arns | Map of composite alarm names to their ARNs |

## Examples

### Basic CloudWatch Dashboard

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/basic:
      vars:
        region: us-west-2
        
        # Dashboard
        create_dashboard: true
        dashboard_name: "system-overview"
        dashboard_body: |
          {
            "widgets": [
              {
                "type": "text",
                "x": 0,
                "y": 0,
                "width": 24,
                "height": 1,
                "properties": {
                  "markdown": "# System Overview Dashboard"
                }
              },
              {
                "type": "metric",
                "x": 0,
                "y": 1,
                "width": 12,
                "height": 6,
                "properties": {
                  "metrics": [
                    [ "AWS/EC2", "CPUUtilization", "InstanceId", "${dep.ec2.outputs.instance_id}" ]
                  ],
                  "view": "timeSeries",
                  "stacked": false,
                  "region": "us-west-2",
                  "title": "EC2 CPU Utilization",
                  "period": 300,
                  "stat": "Average"
                }
              },
              {
                "type": "metric",
                "x": 12,
                "y": 1,
                "width": 12,
                "height": 6,
                "properties": {
                  "metrics": [
                    [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${dep.rds.outputs.db_instance_id}" ]
                  ],
                  "view": "timeSeries",
                  "stacked": false,
                  "region": "us-west-2",
                  "title": "RDS CPU Utilization",
                  "period": 300,
                  "stat": "Average"
                }
              }
            ]
          }
        
        # Tags
        tags:
          Environment: dev
          Project: monitoring
```

### Comprehensive Production Monitoring

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/production:
      vars:
        region: us-west-2
        
        # SNS Topic for Alerts
        create_sns_topic: true
        sns_topic_name: "production-alerts"
        sns_subscriptions:
          - protocol: "email"
            endpoint: "oncall@example.com"
          - protocol: "sms"
            endpoint: "+15551234567"
        
        # EC2 Alarms
        ec2_alarms:
          cpu_high:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "CPUUtilization"
            namespace: "AWS/EC2"
            period: 300
            statistic: "Average"
            threshold: 80
            alarm_description: "EC2 CPU utilization is too high"
            actions_enabled: true
            
          cpu_critical:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "CPUUtilization"
            namespace: "AWS/EC2"
            period: 300
            statistic: "Average"
            threshold: 90
            alarm_description: "EC2 CPU utilization is critically high"
            actions_enabled: true
            
          memory_high:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "mem_used_percent"
            namespace: "CWAgent"
            period: 300
            statistic: "Average"
            threshold: 80
            alarm_description: "EC2 memory utilization is high"
            actions_enabled: true
        
        # RDS Alarms
        rds_alarms:
          high_cpu:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "CPUUtilization"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 80
            alarm_description: "RDS CPU utilization is high"
            actions_enabled: true
            
          storage_low:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "LessThanThreshold"
            evaluation_periods: 1
            metric_name: "FreeStorageSpace"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 10737418240  # 10 GB in bytes
            alarm_description: "RDS free storage space is low"
            actions_enabled: true
            
          connections_high:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "DatabaseConnections"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 100
            alarm_description: "RDS database connections are high"
            actions_enabled: true
        
        # Lambda Alarms
        lambda_alarms:
          errors:
            function_name: ${dep.lambda.outputs.function_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 1
            metric_name: "Errors"
            namespace: "AWS/Lambda"
            period: 300
            statistic: "Sum"
            threshold: 1
            alarm_description: "Lambda function has errors"
            actions_enabled: true
            
          throttles:
            function_name: ${dep.lambda.outputs.function_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 1
            metric_name: "Throttles"
            namespace: "AWS/Lambda"
            period: 300
            statistic: "Sum"
            threshold: 1
            alarm_description: "Lambda function is being throttled"
            actions_enabled: true
            
          duration_high:
            function_name: ${dep.lambda.outputs.function_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "Duration"
            namespace: "AWS/Lambda"
            period: 300
            statistic: "Average"
            threshold: 5000  # 5 seconds in milliseconds
            alarm_description: "Lambda function duration is high"
            actions_enabled: true
        
        # API Gateway Alarms
        api_gateway_alarms:
          high_latency:
            api_name: ${dep.apigateway.outputs.api_name}
            stage_name: "prod"
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "Latency"
            namespace: "AWS/ApiGateway"
            period: 300
            statistic: "Average"
            threshold: 1000  # 1 second in milliseconds
            alarm_description: "API Gateway latency is high"
            actions_enabled: true
            
          error_rate:
            api_name: ${dep.apigateway.outputs.api_name}
            stage_name: "prod"
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "5XXError"
            namespace: "AWS/ApiGateway"
            period: 300
            statistic: "Average"
            threshold: 0.05  # 5% error rate
            alarm_description: "API Gateway 5XX error rate is high"
            actions_enabled: true
        
        # Log Groups and Metric Filters
        log_groups:
          application:
            name: "/app/production"
            retention_in_days: 90
            metric_filters:
              - name: "ErrorFilter"
                pattern: "ERROR"
                metric_name: "ApplicationErrors"
                metric_namespace: "CustomMetrics"
                metric_value: "1"
                default_value: "0"
                
              - name: "WarningFilter"
                pattern: "WARN"
                metric_name: "ApplicationWarnings"
                metric_namespace: "CustomMetrics"
                metric_value: "1"
                default_value: "0"
                
              - name: "LatencyFilter"
                pattern: "LATENCY: * ms"
                metric_name: "ApplicationLatency"
                metric_namespace: "CustomMetrics"
                metric_value: "$1"
                default_value: "0"
          
          security:
            name: "/security/audit"
            retention_in_days: 365
            metric_filters:
              - name: "AuthFailureFilter"
                pattern: "Authentication failure"
                metric_name: "AuthFailures"
                metric_namespace: "SecurityMetrics"
                metric_value: "1"
                default_value: "0"
        
        # Composite Alarms
        composite_alarms:
          system_critical:
            alarm_name: "SystemCriticalState"
            alarm_description: "Multiple critical alarms are in ALARM state"
            alarm_rule: "ALARM(${module.monitoring.ec2_alarms.cpu_critical}) AND (ALARM(${module.monitoring.rds_alarms.high_cpu}) OR ALARM(${module.monitoring.api_gateway_alarms.error_rate}))"
            actions_enabled: true
        
        # Tags
        tags:
          Environment: production
          Project: core-services
```

### CloudWatch Logs and Custom Metrics

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/logs:
      vars:
        region: us-west-2
        
        # Log Groups and Metric Filters
        log_groups:
          api_logs:
            name: "/api/gateway/logs"
            retention_in_days: 90
            metric_filters:
              - name: "ResponseTimeFilter"
                pattern: "[timestamp, requestId, method, status, uri, responseTime]"
                metric_name: "ResponseTime"
                metric_namespace: "ApiMetrics"
                metric_value: "$responseTime"
                default_value: "0"
                dimensions:
                  - name: "Method"
                    value: "$method"
                  - name: "Status"
                    value: "$status"
                  - name: "Uri"
                    value: "$uri"
                
              - name: "ErrorFilter"
                pattern: "[timestamp, requestId, method, status=4*, uri, responseTime]"
                metric_name: "ClientErrors"
                metric_namespace: "ApiMetrics"
                metric_value: "1"
                default_value: "0"
                dimensions:
                  - name: "Method"
                    value: "$method"
                  - name: "Uri"
                    value: "$uri"
                
              - name: "ServerErrorFilter"
                pattern: "[timestamp, requestId, method, status=5*, uri, responseTime]"
                metric_name: "ServerErrors"
                metric_namespace: "ApiMetrics"
                metric_value: "1"
                default_value: "0"
                dimensions:
                  - name: "Method"
                    value: "$method"
                  - name: "Uri"
                    value: "$uri"
        
        # Custom Alarms based on Metric Filters
        custom_metric_alarms:
          high_response_time:
            alarm_name: "HighResponseTime"
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "ResponseTime"
            namespace: "ApiMetrics"
            period: 300
            statistic: "Average"
            threshold: 500
            alarm_description: "API response time is high"
            dimensions:
              Method: "POST"
              Uri: "/api/v1/checkout"
            actions_enabled: true
            
          high_server_errors:
            alarm_name: "HighServerErrors"
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 1
            metric_name: "ServerErrors"
            namespace: "ApiMetrics"
            period: 60
            statistic: "Sum"
            threshold: 5
            alarm_description: "High number of server errors"
            actions_enabled: true
        
        # Tags
        tags:
          Environment: production
          Project: api-monitoring
```

## Implementation Best Practices

1. **Dashboard Design**:
   - Group related metrics together
   - Use a consistent layout and organization
   - Include both high-level overview and detailed metrics
   - Use appropriate visualization types for different metrics
   - Consider using dashboard variables for dynamic filtering

2. **Alarm Configuration**:
   - Set appropriate thresholds based on baseline metrics
   - Use multiple evaluation periods to avoid false alarms
   - Configure different severity levels for the same metric
   - Include clear alarm descriptions with troubleshooting steps
   - Test alarms by triggering them manually

3. **Log Management**:
   - Set appropriate retention periods based on compliance requirements
   - Use metric filters to extract valuable insights from logs
   - Define structured logging patterns in your applications
   - Consider using CloudWatch Logs Insights for ad-hoc analysis
   - Monitor log group storage usage

4. **Cost Optimization**:
   - Be mindful of high-resolution metrics that can increase costs
   - Use composite alarms instead of duplicating alarm logic
   - Set appropriate log retention periods
   - Delete unused dashboards, alarms, and log groups
   - Consider using Contributor Insights instead of custom parsing