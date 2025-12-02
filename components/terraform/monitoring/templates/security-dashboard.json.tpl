{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["CloudTrailMetrics", "UnauthorizedAPICalls", {"stat": "Sum"}],
          [".", "RootAccountUsage", {"stat": "Sum"}],
          [".", "IAMPolicyChanges", {"stat": "Sum"}],
          [".", "SecurityGroupChanges", {"stat": "Sum"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Security Events",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/GuardDuty", "HighSeverityFindings", {"stat": "Sum", "label": "High Severity"}],
          [".", "MediumSeverityFindings", {"stat": "Sum", "label": "Medium Severity"}],
          [".", "LowSeverityFindings", {"stat": "Sum", "label": "Low Severity"}]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${region}",
        "title": "GuardDuty Findings by Severity",
        "period": 3600
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/SecurityHub", "Findings", {"stat": "Sum"}]
        ],
        "view": "singleValue",
        "region": "${region}",
        "title": "Total Security Hub Findings",
        "period": 300,
        "setPeriodToTimeRange": true
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, sourceIPAddress, errorCode | filter errorCode = 'AccessDenied' or errorCode = 'UnauthorizedOperation' | sort @timestamp desc | limit 50",
        "region": "${region}",
        "title": "Failed Authentication Attempts",
        "stacked": false
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, sourceIPAddress | filter eventName like /Delete/ or eventName like /Terminate/ or eventName like /Remove/ | sort @timestamp desc | limit 50",
        "region": "${region}",
        "title": "Destructive API Calls",
        "stacked": false
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, requestParameters | filter eventName = 'PutBucketPolicy' or eventName = 'PutBucketAcl' or eventName = 'PutBucketPublicAccessBlock' | sort @timestamp desc | limit 50",
        "region": "${region}",
        "title": "S3 Bucket Policy Changes",
        "stacked": false
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, requestParameters.groupId | filter eventName = 'AuthorizeSecurityGroupIngress' or eventName = 'AuthorizeSecurityGroupEgress' or eventName = 'RevokeSecurityGroupIngress' or eventName = 'RevokeSecurityGroupEgress' | sort @timestamp desc | limit 50",
        "region": "${region}",
        "title": "Security Group Rule Changes",
        "stacked": false
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, requestParameters | filter eventName like /IAM/ and (eventName like /Policy/ or eventName like /Role/ or eventName like /User/) | sort @timestamp desc | limit 50",
        "region": "${region}",
        "title": "IAM Changes",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum"}],
          [".", "Errors", {"stat": "Sum"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${region}",
        "title": "Lambda Security Functions Activity",
        "period": 300
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, sourceIPAddress, userAgent | filter userIdentity.principalId = 'root' | sort @timestamp desc | limit 20",
        "region": "${region}",
        "title": "Root Account Activity",
        "stacked": false
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/SecretsManager", "ResourceAccessCount", {"stat": "Sum"}]
        ],
        "view": "timeSeries",
        "region": "${region}",
        "title": "Secrets Manager Access",
        "period": 300
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, userIdentity.principalId, eventName, sourceIPAddress | filter sourceIPAddress not like /^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)/ and userIdentity.type != 'AWSService' | stats count() by sourceIPAddress | sort count() desc | limit 20",
        "region": "${region}",
        "title": "Top External IPs (Non-Private)",
        "stacked": false
      }
    }
  ]
}
