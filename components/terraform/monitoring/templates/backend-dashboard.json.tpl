{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ApiGateway", "Count", "ApiName", "${api_gateway_name}"],
          [".", "Latency", ".", "."],
          [".", "4XXError", ".", "."],
          [".", "5XXError", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Overview",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{~ for lambda_function in lambda_functions ~}
          ["AWS/Lambda", "Duration", "FunctionName", "${lambda_function}"],
          [".", "Errors", ".", "."],
          [".", "Throttles", ".", "."],
          %{~ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Functions Performance",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{~ for rds_instance in rds_instances ~}
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${rds_instance}"],
          [".", "DatabaseConnections", ".", "."],
          [".", "ReadLatency", ".", "."],
          [".", "WriteLatency", ".", "."],
          %{~ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Performance",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["ContainerInsights", "pod_cpu_utilization", "ClusterName", "${cluster_name}", "Namespace", "backend-services"],
          [".", "pod_memory_utilization", ".", ".", ".", "."],
          [".", "pod_network_rx_bytes", ".", ".", ".", "."],
          [".", "pod_network_tx_bytes", ".", ".", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EKS Backend Services",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{~ for load_balancer in load_balancers ~}
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "${load_balancer}"],
          [".", "RequestCount", ".", "."],
          [".", "HTTPCode_Target_2XX_Count", ".", "."],
          [".", "HTTPCode_Target_4XX_Count", ".", "."],
          [".", "HTTPCode_Target_5XX_Count", ".", "."],
          %{~ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Application Load Balancers",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{~ for cache_cluster in elasticache_clusters ~}
          ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${cache_cluster}"],
          [".", "FreeableMemory", ".", "."],
          [".", "CurrConnections", ".", "."],
          [".", "Evictions", ".", "."],
          %{~ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "ElastiCache Performance",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 18,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/function' | fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100",
        "region": "${region}",
        "title": "Recent Errors from Lambda Functions",
        "view": "table"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 24,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          ["BusinessMetrics/${environment}", "user_registrations"],
          [".", "api_calls_per_minute"],
          [".", "active_users"],
          [".", "error_rate"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Business Metrics",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 8,
      "y": 24,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/Billing", "EstimatedCharges", "Currency", "USD"],
          ["AWS/TrustedAdvisor", "YellowResources", "CheckName", "Cost Optimization"],
          [".", "RedResources", ".", "."]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "us-east-1",
        "title": "Cost Monitoring",
        "period": 86400,
        "stat": "Maximum"
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 24,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/X-Ray", "TracesReceived"],
          [".", "LatencyHigh"],
          [".", "ErrorRate"],
          [".", "ResponseTimeHigh"]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Distributed Tracing (X-Ray)",
        "period": 300,
        "stat": "Average"
      }
    }
  ]
}