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
          [ "AWS/EC2", "CPUUtilization", { "stat": "Average" } ],
          [ "...", { "stat": "Maximum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EC2 CPU Utilization",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100,
            "label": "Percent",
            "showUnits": false
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "High CPU Warning",
              "value": 80,
              "fill": "above",
              "color": "#ff7f0e"
            }
          ]
        }
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
          [ "AWS/RDS", "CPUUtilization", { "stat": "Average" } ],
          [ ".", "DatabaseConnections", { "stat": "Average", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Performance",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100,
            "label": "CPU %",
            "showUnits": false
          },
          "right": {
            "label": "Connections",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/RDS", "ReadLatency", { "stat": "Average" } ],
          [ ".", "WriteLatency", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Latency",
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
      "x": 8,
      "y": 6,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/RDS", "ReadIOPS", { "stat": "Average" } ],
          [ ".", "WriteIOPS", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS IOPS",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "IOPS",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 6,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/RDS", "FreeStorageSpace", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS Free Storage",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Bytes",
            "showUnits": false
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Low Storage Warning",
              "value": 2147483648,
              "fill": "below",
              "color": "#d62728"
            }
          ]
        }
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
          [ "AWS/Lambda", "Duration", { "stat": "Average" } ],
          [ "...", { "stat": "p99" } ],
          [ ".", "Errors", { "stat": "Sum", "yAxis": "right" } ],
          [ ".", "Throttles", { "stat": "Sum", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Performance & Errors",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Duration (ms)",
            "showUnits": false
          },
          "right": {
            "label": "Count",
            "showUnits": false
          }
        }
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
          [ "AWS/Lambda", "ConcurrentExecutions", { "stat": "Maximum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Concurrent Executions",
        "period": 60
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/DynamoDB", "SuccessfulRequestLatency", "Operation", "GetItem", { "stat": "Average" } ],
          [ "...", "PutItem", { "stat": "Average" } ],
          [ "...", "Query", { "stat": "Average" } ],
          [ "...", "Scan", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "DynamoDB Request Latency",
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
      "x": 12,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/DynamoDB", "UserErrors", { "stat": "Sum" } ],
          [ ".", "SystemErrors", { "stat": "Sum" } ],
          [ ".", "ThrottledRequests", { "stat": "Sum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "DynamoDB Errors & Throttles",
        "period": 300
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
          [ "AWS/ECS", "CPUUtilization", { "stat": "Average" } ],
          [ ".", "MemoryUtilization", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "ECS Resource Utilization",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100,
            "label": "Percent",
            "showUnits": false
          }
        }
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
          [ "AWS/EKS", "cluster_failed_node_count", { "stat": "Average" } ],
          [ ".", "cluster_node_count", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EKS Cluster Health",
        "period": 300
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
          [ "AWS/ApiGateway", "Latency", { "stat": "Average" } ],
          [ "...", { "stat": "p99" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Latency",
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
      "x": 0,
      "y": 30,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/NetworkELB", "HealthyHostCount", { "stat": "Average" } ],
          [ ".", "UnHealthyHostCount", { "stat": "Average" } ],
          [ "AWS/ApplicationELB", "TargetResponseTime", { "stat": "Average", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Load Balancer Health & Performance",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Host Count",
            "showUnits": false
          },
          "right": {
            "label": "Response Time (s)",
            "showUnits": false
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 36,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## Performance Optimization Tips\n\n- **RDS**: Consider read replicas for read-heavy workloads, enable Performance Insights\n- **Lambda**: Optimize memory allocation, use Provisioned Concurrency for consistent performance\n- **DynamoDB**: Use DAX for caching, enable auto-scaling, review access patterns\n- **EC2**: Right-size instances, enable auto-scaling, use Spot instances for fault-tolerant workloads\n- **ECS/EKS**: Configure resource requests/limits, use horizontal pod autoscaling"
      }
    }
  ]
}
