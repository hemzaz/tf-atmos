{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/EC2", "CPUUtilization", { "stat": "Average" }],
          [".", "NetworkIn", { "stat": "Sum", "yAxis": "right" }],
          [".", "NetworkOut", { "stat": "Sum", "yAxis": "right" }]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EC2 Overview",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "CPU %",
            "showUnits": false
          },
          "right": {
            "label": "Network Bytes",
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
          ["AWS/RDS", "CPUUtilization", {"stat": "Average", "label": "${instance}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS CPU Utilization",
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
          %{ for instance in rds_instances ~}
          ["AWS/RDS", "DatabaseConnections", {"stat": "Average", "label": "${instance}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Database Connections",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for instance in rds_instances ~}
          ["AWS/RDS", "FreeStorageSpace", {"stat": "Average", "label": "${instance}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Free Storage Space",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Bytes",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for lb in load_balancers ~}
          ["AWS/ApplicationELB", "TargetResponseTime", {"stat": "Average", "label": "${lb}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Application Load Balancer Response Time",
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
          %{ for lb in load_balancers ~}
          ["AWS/ApplicationELB", "RequestCount", {"stat": "Sum", "label": "${lb}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "Application Load Balancer Requests",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for func in lambda_functions ~}
          ["AWS/Lambda", "Invocations", {"stat": "Sum", "label": "${func}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "Lambda Invocations",
        "period": 300
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
        "title": "Lambda Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          %{ for func in lambda_functions ~}
          ["AWS/Lambda", "Duration", {"stat": "Average", "label": "${func}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Duration",
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
          %{ for cache in elasticache_clusters ~}
          ["AWS/ElastiCache", "CPUUtilization", {"stat": "Average", "label": "${cache}"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "ElastiCache CPU Utilization",
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
          %{ for cache in elasticache_clusters ~}
          ["AWS/ElastiCache", "CacheHits", {"stat": "Sum", "label": "${cache} Hits"}],
          [".", "CacheMisses", {"stat": "Sum", "label": "${cache} Misses"}],
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "ElastiCache Hit/Miss Ratio",
        "period": 300
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/VPC", "BytesIn", {"stat": "Sum", "label": "Bytes In"}],
          [".", "BytesOut", {"stat": "Sum", "label": "Bytes Out"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "VPC Network Traffic",
        "period": 300
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/lambda' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20",
        "region": "${region}",
        "title": "Recent Lambda Errors",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Billing", "EstimatedCharges", {"stat": "Maximum", "label": "Estimated Charges"}]
        ],
        "view": "singleValue",
        "region": "us-east-1",
        "title": "Estimated AWS Charges (USD)",
        "period": 21600,
        "setPeriodToTimeRange": true
      }
    }
  ]
}
