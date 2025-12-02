# ElastiCache Redis Advanced

Production-ready Redis cluster with cluster mode, Multi-AZ, encryption, and auto-failover.

## Features

- Cluster mode enabled/disabled
- Multi-AZ with automatic failover
- Encryption at rest (KMS) and in transit (TLS)
- Redis AUTH token support
- Automated backups (0-35 days retention)
- CloudWatch logging (slow log, engine log)
- Parameter group tuning
- CloudWatch alarms
- Cost optimization features

## Usage

```hcl
module "redis" {
  source = "../../_library/data-layer/elasticache-redis"

  name_prefix = "myapp"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.database_subnet_ids
  
  node_type            = "cache.r7g.large"
  engine_version       = "7.0"
  num_cache_nodes      = 2
  
  enable_multi_az          = true
  enable_automatic_failover = true
  
  enable_encryption_at_rest    = true
  enable_encryption_in_transit = true
  auth_token                   = "MySecureToken16Plus"
  
  snapshot_retention_limit = 7
  
  allowed_security_group_ids = [module.app.security_group_id]
  
  tags = {
    Team = "backend"
  }
}
```

## Cost

- **cache.r7g.large**: ~$0.218/hour = $159/month per node
- **cache.r7g.xlarge**: ~$0.436/hour = $318/month per node
- **Backups**: $0.085/GB/month
- **Data transfer**: Variable

Estimated: $320-650/month for 2-node cluster.

## Inputs

See [variables.tf](./variables.tf).

## Outputs

See [outputs.tf](./outputs.tf).
