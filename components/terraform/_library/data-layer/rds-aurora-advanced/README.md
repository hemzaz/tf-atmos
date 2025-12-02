# RDS Aurora Advanced

Enterprise-grade Aurora cluster with multi-AZ deployment, auto-scaling read replicas, Performance Insights, Enhanced Monitoring, and automated secrets rotation.

## Features

- **High Availability**: Multi-AZ deployment with automatic failover
- **Auto-Scaling**: Read replica auto-scaling based on CPU and connections (1-15 replicas)
- **Serverless v2**: Optional serverless scaling (0.5-128 ACUs)
- **Performance Insights**: Advanced monitoring with 7-731 day retention
- **Enhanced Monitoring**: Real-time OS metrics at 1-60 second intervals
- **Secrets Rotation**: Automatic password rotation (1-365 days)
- **Global Database**: Cross-region replication for disaster recovery
- **Security**: KMS encryption, IAM auth, deletion protection
- **Cost Optimization**: Auto-scaling, serverless v2, configurable backups

## Usage

### Basic Example

```hcl
module "aurora" {
  source = "../../_library/data-layer/rds-aurora-advanced"

  name_prefix = "myapp"
  environment = "prod"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
  
  engine          = "aurora-postgresql"
  engine_version  = "15.4"
  instance_class  = "db.r6g.large"
  instance_count  = 2
  
  database_name   = "myappdb"
  master_username = "dbadmin"
  
  allowed_cidr_blocks = ["10.0.0.0/16"]
  
  tags = {
    Team = "platform"
  }
}
```

### Serverless v2 Example

```hcl
module "aurora_serverless" {
  source = "../../_library/data-layer/rds-aurora-advanced"

  name_prefix = "myapp"
  environment = "dev"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnet_ids
  
  engine                     = "aurora-postgresql"
  enable_serverlessv2        = true
  serverlessv2_min_capacity  = 0.5
  serverlessv2_max_capacity  = 16
  instance_count             = 2
  
  tags = {
    Environment = "development"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0, < 6.0.0 |
| random | >= 3.5.0 |

## Cost Estimation

**Provisioned (db.r6g.large, 2 instances)**: ~$450-550/month
- Control plane: included
- Instances: $220/instance/month × 2 = $440
- Storage (100GB): $40
- Backups: $10-30
- Data transfer: $10-20

**Serverless v2 (16 max ACU)**: ~$90-150/month
- ACU hours: $0.12/ACU-hour
- Variable based on usage
- Storage: $40
- Lower cost for variable workloads

**Add-ons**:
- Performance Insights (>7 days): $0.09/vCPU/day
- Enhanced Monitoring: $1.50/instance/month
- Cross-region replication: Data transfer costs

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for resource naming | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| vpc_id | VPC ID for deployment | `string` | n/a | yes |
| subnet_ids | Database subnet IDs (min 2) | `list(string)` | n/a | yes |
| engine | Database engine (aurora-postgresql\|aurora-mysql) | `string` | `"aurora-postgresql"` | no |
| instance_count | Number of instances | `number` | `2` | no |
| enable_serverlessv2 | Enable Serverless v2 | `bool` | `false` | no |
| enable_autoscaling | Enable read replica auto-scaling | `bool` | `true` | no |
| enable_performance_insights | Enable Performance Insights | `bool` | `true` | no |
| enable_enhanced_monitoring | Enable Enhanced Monitoring | `bool` | `true` | no |
| backup_retention_period | Backup retention (1-35 days) | `number` | `7` | no |

See [variables.tf](./variables.tf) for all 60+ configuration options.

## Outputs

| Name | Description |
|------|-------------|
| cluster_endpoint | Writer endpoint for read-write connections |
| cluster_reader_endpoint | Reader endpoint for read-only connections (load-balanced) |
| cluster_id | Cluster identifier |
| master_password_secret_arn | Secrets Manager ARN for credentials |
| security_group_id | Security group ID |
| connection_string_writer | Connection string template for writer |
| connection_string_reader | Connection string template for reader |

See [outputs.tf](./outputs.tf) for all 40+ outputs.

## Examples

- [Complete](./examples/complete/) - Full-featured production cluster
- [Basic](./examples/basic/) - Simple cluster with defaults
- [Multi-Region](./examples/multi-region/) - Global database setup

## Security

- ✅ Encryption at rest (KMS)
- ✅ Encryption in transit (SSL/TLS required)
- ✅ Secrets Manager integration
- ✅ Automatic password rotation
- ✅ IAM database authentication
- ✅ Deletion protection
- ✅ Network isolation (private subnets)
- ✅ Security group validation

## Performance Tuning

### PostgreSQL
- `shared_preload_libraries`: pg_stat_statements, auto_explain
- `log_min_duration_statement`: 1000ms
- `auto_explain.log_min_duration`: 5000ms
- `rds.force_ssl`: enabled

### MySQL
- `slow_query_log`: enabled
- `long_query_time`: 1s
- `log_queries_not_using_indexes`: enabled
- `require_secure_transport`: ON

## Troubleshooting

### High CPU
- Scale up instance class or enable auto-scaling
- Review Performance Insights for slow queries
- Check connection pooling configuration

### Connection Limits
- Enable auto-scaling for read replicas
- Increase instance class
- Review application connection pooling
- Monitor `DatabaseConnections` metric

### Storage Growth
- Review backup retention period
- Check for large tables/indexes
- Enable Aurora Storage Auto-Scaling

## Migration Guide

### From RDS PostgreSQL/MySQL
1. Take snapshot of existing RDS instance
2. Restore snapshot to Aurora cluster
3. Update application connection strings
4. Test application thoroughly
5. Cutover during maintenance window

### From Aurora Provisioned to Serverless v2
1. Set `enable_serverlessv2 = true`
2. Set `instance_class = "db.serverless"`
3. Configure min/max capacity
4. Apply during maintenance window

## Maintainers

- **Team**: Database Engineering / Platform Engineering
- **Primary**: dba-team@example.com
- **Backup**: platform-team@example.com
- **Slack**: #database-support

## License

Part of the tf-atmos Alexandria Library.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history.
