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
          [ "AWS/Billing", "EstimatedCharges", { "stat": "Maximum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Estimated AWS Charges",
        "period": 86400,
        "yAxis": {
          "left": {
            "label": "USD",
            "showUnits": false
          }
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
          [ "AWS/EC2", "NetworkIn", { "stat": "Sum", "label": "Data In" } ],
          [ ".", "NetworkOut", { "stat": "Sum", "label": "Data Out" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EC2 Data Transfer",
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
      "x": 0,
      "y": 6,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/RDS", "DatabaseConnections", { "stat": "Average" } ]
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
      "x": 8,
      "y": 6,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Duration", { "stat": "Average" } ],
          [ ".", "Invocations", { "stat": "Sum", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Execution Metrics",
        "period": 300,
        "yAxis": {
          "left": {
            "label": "Duration (ms)",
            "showUnits": false
          },
          "right": {
            "label": "Invocations",
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
          [ "AWS/DynamoDB", "ConsumedReadCapacityUnits", { "stat": "Sum" } ],
          [ ".", "ConsumedWriteCapacityUnits", { "stat": "Sum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "DynamoDB Capacity Usage",
        "period": 300
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
          [ "AWS/S3", "BucketSizeBytes", "StorageType", "StandardStorage", { "stat": "Average" } ],
          [ "...", "StandardIAStorage", { "stat": "Average" } ],
          [ "...", "GlacierStorage", { "stat": "Average" } ]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "S3 Storage by Class",
        "period": 86400,
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
      "x": 12,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/EBS", "VolumeReadBytes", { "stat": "Sum" } ],
          [ ".", "VolumeWriteBytes", { "stat": "Sum" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "EBS Volume I/O",
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
      "type": "log",
      "x": 0,
      "y": 18,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/${environment}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20",
        "region": "${region}",
        "stacked": false,
        "title": "Recent Lambda Errors",
        "view": "table"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 24,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "## Cost Optimization Recommendations\n\n- Review unused EBS volumes and snapshots\n- Consider Reserved Instances for steady-state workloads\n- Enable S3 Intelligent-Tiering for automatic cost optimization\n- Review CloudWatch Logs retention periods\n- Monitor data transfer costs across regions"
      }
    }
  ]
}
