# Network Firewall

AWS Network Firewall with stateful/stateless rules, domain filtering, and IPS capabilities.

## Features

- Stateful and stateless rule groups
- Domain filtering (allow/deny lists)
- Suricata-compatible IPS rules
- Multi-AZ deployment
- S3 and CloudWatch logging
- Centralized inspection VPC pattern
- Delete and change protection

## Usage

```hcl
module "network_firewall" {
  source = "./_library/networking/network-firewall"

  name_prefix = "prod"
  environment = "production"
  vpc_id      = "vpc-123456"
  subnet_ids  = ["subnet-abc123", "subnet-def456"]

  stateful_domain_rule_groups = {
    allow_domains = {
      capacity             = 100
      generated_rules_type = "ALLOWLIST"
      target_types         = ["HTTP_HOST", "TLS_SNI"]
      targets              = [".example.com", ".amazonaws.com"]
    }
  }

  enable_flow_logs_to_s3        = true
  enable_alert_logs_to_cloudwatch = true
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
