# OpenSearch

Production-ready Amazon OpenSearch domain with multi-AZ, encryption, fine-grained access control, and Cognito authentication.

## Features

- Multi-AZ deployment with replicas
- Encryption at rest and in transit
- Fine-grained access control
- Cognito authentication integration
- Dedicated master nodes (optional)
- Warm and cold storage tiers
- Auto-Tune for performance optimization
- CloudWatch alarms and monitoring
- VPC deployment support
- Index state management policies

## Usage

```hcl
module "opensearch" {
  source = "./_library/data-platform/opensearch"

  domain_name    = "prod-logs"
  engine_version = "OpenSearch_2.11"

  instance_type  = "r6g.large.search"
  instance_count = 3

  dedicated_master_enabled = true
  dedicated_master_type    = "r6g.large.search"
  dedicated_master_count   = 3

  zone_awareness_enabled   = true
  availability_zone_count  = 3

  ebs_volume_size = 500
  ebs_volume_type = "gp3"
  ebs_iops        = 3000
  ebs_throughput  = 125

  kms_key_id = aws_kms_key.opensearch.id

  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id
  allowed_cidr_blocks = [
    aws_vpc.main.cidr_block
  ]

  master_user_arn = aws_iam_role.opensearch_admin.arn

  access_principals = [
    aws_iam_role.app_role.arn
  ]

  auto_tune_enabled = true

  enable_monitoring = true
  alarm_actions     = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "production"
    Service     = "logging"
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
