# DynamoDB Advanced

Production-ready DynamoDB table with auto-scaling, global tables, streams, and comprehensive monitoring.

## Features

- On-demand or provisioned capacity modes
- Auto-scaling for provisioned mode (5-100 capacity units)
- Global tables for multi-region replication
- DynamoDB Streams for change data capture
- Point-in-time recovery (PITR)
- Encryption at rest with KMS
- TTL for automatic item expiration
- GSI and LSI support
- Deletion protection
- Standard or Infrequent Access table class

## Usage

```hcl
module "dynamodb" {
  source = "../../_library/data-layer/dynamodb-advanced"

  name_prefix = "myapp"
  environment = "prod"
  table_name  = "users"
  
  billing_mode = "PAY_PER_REQUEST"  # or "PROVISIONED"
  
  hash_key      = "user_id"
  hash_key_type = "S"
  range_key     = "timestamp"
  range_key_type = "N"
  
  attributes = [
    { name = "email", type = "S" },
    { name = "status", type = "S" }
  ]
  
  global_secondary_indexes = [
    {
      name     = "EmailIndex"
      hash_key = "email"
      projection_type = "ALL"
    }
  ]
  
  enable_streams = true
  enable_point_in_time_recovery = true
  enable_deletion_protection = true
  
  tags = {
    Team = "backend"
  }
}
```

## Cost

- **On-Demand**: $1.25/million write requests, $0.25/million read requests, $0.25/GB storage
- **Provisioned**: ~$0.47/WCU/month, ~$0.09/RCU/month
- **Global Tables**: 2x write cost for replicated writes
- **Streams**: $0.02 per 100k read requests
- **PITR**: $0.20/GB/month

Estimated monthly: $10-200 depending on throughput and storage.

## Inputs

See [variables.tf](./variables.tf) for all 30+ options.

## Outputs

See [outputs.tf](./outputs.tf) for complete list.
