{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "\n# ${environment} Environment Dashboard\n"
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
          [ "AWS/EC2", "CPUUtilization", "VPC", "${vpc_id}" ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "VPC CPU Utilization",
        "period": 300
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
          %{ for i, rds in rds_instances ~}
          ${i > 0 ? "," : ""}[ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${rds}" ]
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "RDS CPU Utilization",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 7,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{ for i, ecs in ecs_clusters ~}
          ${i > 0 ? "," : ""}[ "AWS/ECS", "CPUUtilization", "ClusterName", "${ecs}" ]
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "ECS CPU Utilization",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 7,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          %{ for i, lambda in lambda_functions ~}
          ${i > 0 ? "," : ""}[ "AWS/Lambda", "Invocations", "FunctionName", "${lambda}" ]
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Invocations",
        "period": 300
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
          %{ for i, lb in load_balancers ~}
          ${i > 0 ? "," : ""}[ "AWS/ApplicationELB", "RequestCount", "LoadBalancer", "${lb}" ]
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Load Balancer Requests",
        "period": 300
      }
    }
  ]
}