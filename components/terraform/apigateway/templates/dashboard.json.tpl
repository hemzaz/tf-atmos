{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "\n# ${environment} API Gateway Dashboard\n"
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
          [ "AWS/ApiGateway", "Count", "ApiName", "${api_name}" ],
          [ ".", "4XXError", ".", "." ],
          [ ".", "5XXError", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Request Count and Errors",
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
          [ "AWS/ApiGateway", "Latency", "ApiName", "${api_name}", { "stat": "Average" } ],
          [ "...", { "stat": "p90" } ],
          [ "...", { "stat": "p95" } ],
          [ "...", { "stat": "p99" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Latency",
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
          [ "AWS/ApiGateway", "IntegrationLatency", "ApiName", "${api_name}", { "stat": "Average" } ],
          [ "...", { "stat": "p90" } ],
          [ "...", { "stat": "p95" } ],
          [ "...", { "stat": "p99" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Integration Latency",
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
          [ "AWS/ApiGateway", "IntegrationError", "ApiName", "${api_name}" ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Integration Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 13,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "CacheHitCount", "ApiName", "${api_name}" ],
          [ ".", "CacheMissCount", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Cache Metrics",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 13,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "ThrottleCount", "ApiName", "${api_name}" ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Throttling",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 19,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "401Error", "ApiName", "${api_name}" ],
          [ ".", "403Error", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Authorization Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 19,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "400Error", "ApiName", "${api_name}" ],
          [ ".", "422Error", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Validation Errors",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 25,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          %{ for stage in api_stages ~}
          [ "AWS/ApiGateway", "Count", "ApiName", "${api_name}", "Stage", "${stage}" ]%{ if stage != api_stages[length(api_stages) - 1] },%{ endif }
          %{ endfor ~}
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "API Gateway Request Count by Stage",
        "period": 300
      }
    }
  ]
}