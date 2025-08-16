# Monitoring Examples

This directory contains examples for implementing AWS CloudWatch monitoring with the Atmos framework.

## Basic CloudWatch Dashboard

Below is an example of how to deploy a basic CloudWatch dashboard to monitor critical resources:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/basic:
      vars:
        enabled: true
        region: us-west-2
        
        # Dashboard Configuration
        create_dashboard: true
        dashboard_name: "system-overview"
        
        # Alarms Configuration
        create_alarms: true
        
        # Service Specific Alarms
        ec2_alarms:
          cpu_utilization_high:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "CPUUtilization"
            namespace: "AWS/EC2"
            period: 300
            statistic: "Average"
            threshold: 80
            alarm_description: "EC2 instance CPU utilization is too high"
            alarm_actions: []  # Add SNS topic ARN for notifications
        
        rds_alarms:
          free_storage_space_low:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "LessThanThreshold"
            evaluation_periods: 1
            metric_name: "FreeStorageSpace"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 10737418240  # 10 GB in bytes
            alarm_description: "RDS free storage space is too low"
            alarm_actions: []
        
        # Tags
        tags:
          Environment: dev
          Project: demo
```

## Advanced Monitoring Setup

For production environments with comprehensive monitoring:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/production:
      vars:
        enabled: true
        region: us-west-2
        
        # Dashboard Configuration
        create_dashboard: true
        dashboard_name: "production-monitoring"
        
        # SNS Topic for Notifications
        create_sns_topic: true
        sns_topic_name: "monitoring-alerts"
        sns_topic_subscriptions: [
          {
            protocol: "email",
            endpoint: "alerts@example.com"
          },
          {
            protocol: "https",
            endpoint: "https://monitoring.example.com/webhooks/cloudwatch"
          }
        ]
        
        # Service Specific Alarms
        ec2_alarms:
          cpu_utilization_high:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 3
            metric_name: "CPUUtilization"
            namespace: "AWS/EC2"
            period: 300
            statistic: "Average"
            threshold: 70
            alarm_description: "EC2 instance CPU utilization is high"
            actions_enabled: true
            
          cpu_utilization_critical:
            instance_id: ${dep.ec2.outputs.instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "CPUUtilization"
            namespace: "AWS/EC2"
            period: 300
            statistic: "Average"
            threshold: 90
            alarm_description: "EC2 instance CPU utilization is critically high"
            actions_enabled: true
        
        rds_alarms:
          free_storage_space_low:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "LessThanThreshold"
            evaluation_periods: 1
            metric_name: "FreeStorageSpace"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 21474836480  # 20 GB in bytes
            alarm_description: "RDS free storage space is low"
            actions_enabled: true
            
          high_cpu:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 3
            metric_name: "CPUUtilization"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 80
            alarm_description: "RDS database CPU utilization is high"
            actions_enabled: true
            
          high_memory:
            db_instance_identifier: ${dep.rds.outputs.db_instance_id}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 3
            metric_name: "FreeableMemory"
            namespace: "AWS/RDS"
            period: 300
            statistic: "Average"
            threshold: 10737418240  # 10 GB in bytes (inverted logic: lower value means higher memory usage)
            alarm_description: "RDS database memory usage is high"
            actions_enabled: true
        
        # ELB Alarms
        elb_alarms:
          high_latency:
            load_balancer_name: ${dep.apigateway.outputs.load_balancer_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 3
            metric_name: "Latency"
            namespace: "AWS/ELB"
            period: 300
            statistic: "Average"
            threshold: 1  # 1 second
            alarm_description: "Load balancer latency is high"
            actions_enabled: true
            
          backend_5xx_errors:
            load_balancer_name: ${dep.apigateway.outputs.load_balancer_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "HTTPCode_Backend_5XX"
            namespace: "AWS/ELB"
            period: 300
            statistic: "Sum"
            threshold: 50
            alarm_description: "Load balancer is experiencing backend 5XX errors"
            actions_enabled: true
        
        # API Gateway Alarms
        api_gateway_alarms:
          high_error_rate:
            api_name: ${dep.apigateway.outputs.api_name}
            stage_name: "prod"
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "5XXError"
            namespace: "AWS/ApiGateway"
            period: 300
            statistic: "Average"
            threshold: 0.05  # 5% error rate
            alarm_description: "API Gateway has a high 5XX error rate"
            actions_enabled: true
        
        # Lambda Alarms
        lambda_alarms:
          high_error_rate:
            function_name: ${dep.lambda.outputs.function_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "Errors"
            namespace: "AWS/Lambda"
            period: 300
            statistic: "Sum"
            threshold: 10
            alarm_description: "Lambda function has a high error rate"
            actions_enabled: true
            
          high_duration:
            function_name: ${dep.lambda.outputs.function_name}
            comparison_operator: "GreaterThanThreshold"
            evaluation_periods: 2
            metric_name: "Duration"
            namespace: "AWS/Lambda"
            period: 300
            statistic: "Average"
            threshold: 5000  # 5 seconds in milliseconds
            alarm_description: "Lambda function execution duration is high"
            actions_enabled: true
        
        # Composite Alarms
        composite_alarms:
          system_critical:
            alarm_name: "SystemCriticalState"
            alarm_description: "Multiple critical alarms are in ALARM state"
            alarm_rule: "ALARM(${dep.monitoring.outputs.ec2_alarms.cpu_utilization_critical}) AND (ALARM(${dep.monitoring.outputs.rds_alarms.high_cpu}) OR ALARM(${dep.monitoring.outputs.api_gateway_alarms.high_error_rate}))"
            actions_enabled: true
        
        # Tags
        tags:
          Environment: production
          Project: core-services
```

## CloudWatch Logs Insights Dashboard

For monitoring application logs:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    monitoring/logs:
      vars:
        enabled: true
        region: us-west-2
        
        # Dashboard Configuration
        create_dashboard: true
        dashboard_name: "application-logs"
        
        # Log Insights Queries
        log_insights_queries:
          error_rates:
            name: "Error Rates by Service"
            log_group_names: [
              "/aws/lambda/${dep.lambda.outputs.function_name}",
              "/aws/apigateway/${dep.apigateway.outputs.api_id}/${dep.apigateway.outputs.stage_name}"
            ]
            query_string: "fields @timestamp, @message | filter @message like /ERROR|Error|error/ | stats count() as error_count by bin(5m)"
            
          latency_distribution:
            name: "API Latency Distribution"
            log_group_names: [
              "/aws/apigateway/${dep.apigateway.outputs.api_id}/${dep.apigateway.outputs.stage_name}"
            ]
            query_string: "fields @timestamp, @message | parse @message /\"responseLatency\":(?<latency>\\d+)/ | stats percentile(latency, 50) as p50, percentile(latency, 90) as p90, percentile(latency, 99) as p99 by bin(5m)"
        
        # Log Metrics Filters
        log_metrics_filters:
          lambda_error:
            name: "LambdaErrorMetric"
            log_group_name: "/aws/lambda/${dep.lambda.outputs.function_name}"
            pattern: "ERROR"
            metric_transformation: {
              name: "ErrorCount",
              namespace: "CustomMetrics/Lambda",
              value: "1"
            }
          
          api_gateway_500:
            name: "ApiGateway500Metric"
            log_group_name: "/aws/apigateway/${dep.apigateway.outputs.api_id}/${dep.apigateway.outputs.stage_name}"
            pattern: "{ $.status = 500 }"
            metric_transformation: {
              name: "500ErrorCount",
              namespace: "CustomMetrics/ApiGateway",
              value: "1"
            }
        
        # Tags
        tags:
          Environment: production
          Project: logs-monitoring
```

## Implementation Notes

1. **Alarm Configuration**:
   - Set thresholds based on historical performance data when available
   - Configure evaluation periods to avoid false alarms from transient spikes
   - Use SNS topics for notification integration with your operational tools

2. **Dashboard Best Practices**:
   - Group related metrics together for better visibility
   - Include both resource utilization and application performance metrics
   - Consider using log insights for deeper application insights

3. **Operational Considerations**:
   - Implement a good alerting strategy to avoid alert fatigue
   - Use composite alarms for complex failure scenarios
   - Document runbooks for each alarm to guide operators

4. **Cost Optimization**:
   - Monitor CloudWatch costs, especially for high-resolution metrics
   - Set appropriate log retention periods
   - Use metric filters to extract application-specific metrics from logs instead of publishing custom metrics directly