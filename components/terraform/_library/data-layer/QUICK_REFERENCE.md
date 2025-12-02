# Alexandria Library Data Layer - Quick Reference Guide

## Module File Paths

```
/Users/elad/PROJ/tf-atmos/components/terraform/_library/data-layer/

├── rds-aurora-advanced/        # Aurora PostgreSQL/MySQL clusters
├── dynamodb-advanced/          # DynamoDB tables with global tables
├── elasticache-redis/          # Redis clusters with encryption
├── rds-postgres/               # Existing RDS PostgreSQL
├── s3-bucket/                  # Existing S3 buckets
└── dynamodb-table/             # Existing DynamoDB tables
```

## Quick Start Examples

### Aurora PostgreSQL Production

```hcl
module "aurora" {
  source = "../../_library/data-layer/rds-aurora-advanced"

  name_prefix = "myapp"
  environment = "prod"
  vpc_id      = "vpc-xxxxx"
  subnet_ids  = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
  
  engine          = "aurora-postgresql"
  engine_version  = "15.4"
  instance_class  = "db.r6g.large"
  instance_count  = 2
  
  enable_autoscaling          = true
  enable_performance_insights = true
  enable_enhanced_monitoring  = true
  
  allowed_cidr_blocks = ["10.0.0.0/16"]
  
  tags = { Team = "backend" }
}

# Outputs
output "writer_endpoint" { value = module.aurora.cluster_endpoint }
output "reader_endpoint" { value = module.aurora.cluster_reader_endpoint }
output "password_secret"  { value = module.aurora.master_password_secret_arn }
```

### DynamoDB with Global Tables

```hcl
module "users_table" {
  source = "../../_library/data-layer/dynamodb-advanced"

  name_prefix = "myapp"
  environment = "prod"
  table_name  = "users"
  
  billing_mode = "PAY_PER_REQUEST"
  
  hash_key      = "user_id"
  hash_key_type = "S"
  
  enable_streams               = true
  enable_point_in_time_recovery = true
  enable_global_tables         = true
  replica_regions              = ["us-west-2", "eu-west-1"]
  
  tags = { Team = "backend" }
}

# Outputs
output "table_name" { value = module.users_table.table_name }
output "stream_arn" { value = module.users_table.stream_arn }
```

### ElastiCache Redis Production

```hcl
module "redis" {
  source = "../../_library/data-layer/elasticache-redis"

  name_prefix = "myapp"
  environment = "prod"
  vpc_id      = "vpc-xxxxx"
  subnet_ids  = ["subnet-xxx", "subnet-yyy"]
  
  node_type       = "cache.r7g.large"
  num_cache_nodes = 2
  
  enable_multi_az              = true
  enable_automatic_failover    = true
  enable_encryption_at_rest    = true
  enable_encryption_in_transit = true
  
  auth_token = "MySecurePassword16CharactersMin"
  
  allowed_security_group_ids = ["sg-xxxxx"]
  
  tags = { Team = "backend" }
}

# Outputs
output "redis_endpoint" { value = module.redis.primary_endpoint_address }
output "redis_port"     { value = module.redis.port }
```

## Cost Comparison

| Module | Dev/Test | Production | HA Production | Notes |
|--------|----------|------------|---------------|-------|
| **Aurora** | $60-80 | $450-550 | $900-1,100 | Add $90-150 for Serverless v2 |
| **DynamoDB** | $10-50 | $30-60 | $60-200 | Global tables double write cost |
| **Redis** | $50-70 | $320-350 | $950-1,000 | Cluster mode: $1,400-1,500 |

## Module Comparison Matrix

| Feature | Aurora | DynamoDB | Redis |
|---------|--------|----------|-------|
| **Type** | Relational | NoSQL Key-Value | In-Memory Cache |
| **Use Cases** | OLTP, Analytics | Serverless, Gaming | Caching, Sessions |
| **Auto-Scaling** | Read replicas | RCU/WCU | Manual scaling |
| **Multi-Region** | Global DB | Global Tables | Manual setup |
| **Backup** | 1-35 days | PITR 35 days | 0-35 days |
| **Encryption** | At rest + transit | At rest | At rest + transit |
| **Max Replicas** | 15 | Unlimited | 5 per shard |

## Key Variables Comparison

### Common Variables (All Modules)
- `name_prefix` - Prefix for naming
- `environment` - Environment name
- `tags` - Resource tags

### Aurora Specific
- `instance_class` - Instance type (db.r6g.large)
- `instance_count` - Number of instances (1-15)
- `enable_serverlessv2` - Use Serverless v2
- `serverlessv2_max_capacity` - Max ACUs (0.5-128)
- `enable_performance_insights` - Enable PI
- `enable_enhanced_monitoring` - Enable EM

### DynamoDB Specific
- `billing_mode` - PAY_PER_REQUEST or PROVISIONED
- `hash_key` - Partition key name
- `range_key` - Sort key name (optional)
- `enable_streams` - Enable DynamoDB Streams
- `enable_global_tables` - Multi-region replication
- `replica_regions` - List of replica regions

### Redis Specific
- `node_type` - Cache node type (cache.r7g.large)
- `num_cache_nodes` - Number of nodes (1-6)
- `enable_cluster_mode` - Enable sharding
- `num_node_groups` - Number of shards
- `auth_token` - Redis AUTH password

## Security Checklist

### Aurora
- [x] Encryption at rest (KMS)
- [x] Encryption in transit (SSL/TLS)
- [x] Secrets Manager for passwords
- [x] Automated password rotation
- [x] IAM authentication
- [x] Private subnets only
- [x] Security groups configured
- [x] Deletion protection enabled

### DynamoDB
- [x] Encryption at rest (KMS)
- [x] Fine-grained IAM policies
- [x] VPC endpoints (external)
- [x] Point-in-time recovery
- [x] Deletion protection enabled
- [x] CloudWatch alarms

### Redis
- [x] Encryption at rest (KMS)
- [x] Encryption in transit (TLS)
- [x] AUTH token enabled
- [x] Private subnets only
- [x] Security groups configured
- [x] Automated backups enabled

## Common Operations

### Aurora

```bash
# Connect to Aurora (PostgreSQL)
psql "postgresql://dbadmin:PASSWORD@cluster-endpoint:5432/database"

# Connect via IAM authentication
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname cluster-endpoint \
  --port 5432 \
  --username dbadmin)
psql "host=cluster-endpoint port=5432 dbname=mydb user=dbadmin sslmode=require"

# View cluster status
aws rds describe-db-clusters --db-cluster-identifier myapp-prod-aurora

# Manual failover
aws rds failover-db-cluster --db-cluster-identifier myapp-prod-aurora
```

### DynamoDB

```bash
# Get item
aws dynamodb get-item \
  --table-name myapp-prod-users \
  --key '{"user_id": {"S": "12345"}}'

# Put item
aws dynamodb put-item \
  --table-name myapp-prod-users \
  --item '{"user_id": {"S": "12345"}, "email": {"S": "user@example.com"}}'

# Query with GSI
aws dynamodb query \
  --table-name myapp-prod-users \
  --index-name EmailIndex \
  --key-condition-expression 'email = :email' \
  --expression-attribute-values '{":email": {"S": "user@example.com"}}'

# Enable PITR
aws dynamodb update-continuous-backups \
  --table-name myapp-prod-users \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
```

### Redis

```bash
# Connect to Redis
redis-cli -h primary-endpoint -p 6379 -a "AUTH_TOKEN" --tls

# Basic commands
SET mykey "Hello World"
GET mykey
KEYS *
INFO replication

# Monitor commands
MONITOR
SLOWLOG GET 10
CONFIG GET maxmemory-policy

# Flush cache (use with caution!)
FLUSHDB  # Flush current database
FLUSHALL # Flush all databases
```

## Monitoring & Alarms

### Aurora CloudWatch Metrics
- `CPUUtilization` - CPU usage
- `DatabaseConnections` - Active connections
- `FreeableMemory` - Available memory
- `ReadLatency` / `WriteLatency` - Query latency
- `AuroraGlobalDBReplicationLag` - Global DB lag

### DynamoDB CloudWatch Metrics
- `ConsumedReadCapacityUnits` - Read capacity used
- `ConsumedWriteCapacityUnits` - Write capacity used
- `UserErrors` - Client-side errors
- `SystemErrors` - Server-side errors
- `ThrottledRequests` - Throttled operations

### Redis CloudWatch Metrics
- `CPUUtilization` - CPU usage
- `DatabaseMemoryUsagePercentage` - Memory usage
- `CacheHits` / `CacheMisses` - Cache hit ratio
- `ReplicationLag` - Replication delay
- `Evictions` - Cache evictions

## Troubleshooting

### Aurora

**Issue**: High CPU usage
- **Solution**: Scale up instance class or add read replicas
- **Check**: Performance Insights for slow queries

**Issue**: Connection pool exhausted
- **Solution**: Increase max_connections parameter or use connection pooling
- **Check**: `DatabaseConnections` metric

### DynamoDB

**Issue**: ThrottledRequests errors
- **Solution**: Increase provisioned capacity or switch to on-demand
- **Check**: `ThrottledRequests` metric, enable auto-scaling

**Issue**: Hot partition
- **Solution**: Redesign partition key for better distribution
- **Check**: Partition-level metrics in CloudWatch

### Redis

**Issue**: High memory usage
- **Solution**: Increase node size or enable cluster mode for sharding
- **Check**: `DatabaseMemoryUsagePercentage` metric

**Issue**: Cache misses
- **Solution**: Review cache key patterns and TTL settings
- **Check**: `CacheHits` / `CacheMisses` ratio

## Module Registry Lookup

```bash
# View module information
cat /Users/elad/PROJ/tf-atmos/components/terraform/_catalog/module-registry.yaml | grep -A 50 "rds-aurora-advanced"

# List all data layer modules
grep -E "^  - id:" /Users/elad/PROJ/tf-atmos/components/terraform/_catalog/module-registry.yaml | grep -A 1 "data/"
```

## Support & Resources

**Documentation**: `/Users/elad/PROJ/tf-atmos/components/terraform/_library/data-layer/{module}/README.md`  
**Examples**: `/{module}/examples/`  
**Standards**: `/Users/elad/PROJ/tf-atmos/docs/MODULE_STANDARDS.md`  
**Slack**: #platform-support, #database-support  
**Email**: platform-team@example.com, dba-team@example.com  

## Next Steps

1. Review module README files for detailed documentation
2. Check examples directory for complete usage patterns
3. Run `terraform plan` to preview changes before applying
4. Enable CloudWatch alarms for production deployments
5. Configure backup and disaster recovery procedures
6. Set up monitoring dashboards in CloudWatch/Grafana
