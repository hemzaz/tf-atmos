{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApiGateway", "Count", {"stat": "Sum", "label": "Total Requests"}],
          [".", "5XXError", {"stat": "Sum", "label": "5XX Errors", "yAxis": "right"}],
          [".", "4XXError", {"stat": "Sum", "label": "4XX Errors", "yAxis": "right"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Request Volume & Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApiGateway", "Latency", {"stat": "Average", "label": "Average"}],
          ["...", {"stat": "p50", "label": "P50"}],
          ["...", {"stat": "p95", "label": "P95"}],
          ["...", {"stat": "p99", "label": "P99"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Latency (ms)",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Milliseconds",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for func in lambda_functions ~}
          ["AWS/Lambda", "Duration", {"stat": "Average", "label": "${func} Avg"}, {"FunctionName": "${func}"}],
          ["...", {"stat": "p99", "label": "${func} P99"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Function Duration",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Milliseconds",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for func in lambda_functions ~}
          ["AWS/Lambda", "Errors", {"stat": "Sum", "label": "${func}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "Lambda Function Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for func in lambda_functions ~}
          ["AWS/Lambda", "ConcurrentExecutions", {"stat": "Maximum", "label": "${func}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Concurrent Executions",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for instance in rds_instances ~}
          ["AWS/RDS", "ReadLatency", {"stat": "Average", "label": "${instance} Read"}],
          [".", "WriteLatency", {"stat": "Average", "label": "${instance} Write"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Database Latency",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Seconds",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for instance in rds_instances ~}
          ["AWS/RDS", "DatabaseConnections", {"stat": "Average", "label": "${instance}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Active Database Connections",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for cache in elasticache_clusters ~}
          ["AWS/ElastiCache", "CacheHitRate", {"stat": "Average", "label": "${cache}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Cache Hit Rate (%)",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for lb in load_balancers ~}
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", {"stat": "Sum", "label": "${lb} 2XX"}],
          [".", "HTTPCode_Target_4XX_Count", {"stat": "Sum", "label": "${lb} 4XX"}],
          [".", "HTTPCode_Target_5XX_Count", {"stat": "Sum", "label": "${lb} 5XX"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "Load Balancer Response Codes",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for lb in load_balancers ~}
          ["AWS/ApplicationELB", "ActiveConnectionCount", {"stat": "Sum", "label": "${lb}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Active Connections",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for lb in load_balancers ~}
          ["AWS/ApplicationELB", "TargetResponseTime", {"stat": "p50", "label": "${lb} P50"}],
          ["...", {"stat": "p95", "label": "${lb} P95"}],
          ["...", {"stat": "p99", "label": "${lb} P99"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Target Response Time Percentiles",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Seconds",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/lambda' | filter @type = 'REPORT' | stats avg(@duration), max(@duration), min(@duration) by bin(5m)",
        "region": "${region}",
        "title": "Lambda Duration Statistics",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["BusinessMetrics/${environment}", "SuccessfulTransactions", {"stat": "Sum"}],
          [".", "FailedTransactions", {"stat": "Sum"}]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "Business Transactions",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["BusinessMetrics/${environment}", "UserSignups", {"stat": "Sum"}],
          [".", "ActiveUsers", {"stat": "Sum"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "User Activity",
        "period": 300
      }
    }
  ]
}
