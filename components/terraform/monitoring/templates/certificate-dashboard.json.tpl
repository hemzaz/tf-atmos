{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "# Certificate Management Dashboard\nMonitoring TLS certificates across AWS ACM and Kubernetes clusters"
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
          [ "AWS/CertificateManager", "DaysToExpiry", "CertificateArn", "${cert_arns[0]}", { "label": "${cert_names[0]}" } ]
          ${join(",\n", [for i in range(1, length(cert_arns)) : "[ \"AWS/CertificateManager\", \"DaysToExpiry\", \"CertificateArn\", \"${cert_arns[i]}\", { \"label\": \"${cert_names[i]}\" } ]"])}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Certificate Days to Expiry",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 90
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Critical",
              "value": 14,
              "color": "#d13212"
            },
            {
              "label": "Warning",
              "value": 30,
              "color": "#ff7f0e"
            }
          ]
        }
      }
    },
    {
      "type": "text",
      "x": 12,
      "y": 1,
      "width": 12,
      "height": 6,
      "properties": {
        "markdown": "## Certificate Status\n\n${join("\n\n", [for i in range(length(cert_arns)) : "- **${cert_names[i]}**\n  - ARN: `${cert_arns[i]}`\n  - Domain: ${cert_domains[i]}\n  - Status: ${cert_statuses[i]}\n  - Expiry: ${cert_expiry_dates[i]}"])}\n\n**Note:** Certificates should be renewed at least 30 days before expiry to avoid service disruption."
      }
    },
    {
      "type": "alarm",
      "x": 0,
      "y": 7,
      "width": 24,
      "height": 6,
      "properties": {
        "title": "Certificate Expiry Alarms",
        "alarms": ${jsonencode(cert_alarm_arns)}
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 13,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/SecretsManager", "ResourceCount", "Service", "Secrets Manager", "Type", "Resource", { "stat": "Sum" } ],
          [ "AWS/SecretsManager", "SuccessfulRequestCount", "Service", "Secrets Manager", "Type", "API", { "stat": "Sum" } ],
          [ "AWS/SecretsManager", "ErrorCount", "Service", "Secrets Manager", "Type", "Error", { "stat": "Sum" } ]
        ],
        "region": "${region}",
        "title": "Secrets Manager Activity (for Certificate Storage)",
        "view": "timeSeries",
        "stacked": false,
        "period": 300
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 19,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/eks/${cluster_name}/external-secrets' | fields @timestamp, @message\n| filter @message like /certificate/ or @message like /secret/\n| sort @timestamp desc\n| limit 100",
        "region": "${region}",
        "title": "External Secrets Operator Logs (Certificate Related)",
        "view": "table"
      }
    }
  ]
}