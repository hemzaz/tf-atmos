# Database Maintenance Runbook

## Routine Maintenance

### Daily Tasks
```bash
# Check replication lag
aws rds describe-db-instances \
  --db-instance-identifier <replica-id> \
  --query 'DBInstances[0].StatusInfos'

# Check slow query log
aws rds describe-db-log-files \
  --db-instance-identifier <instance-id> | grep slowquery

# Monitor connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average,Maximum
```

### Weekly Tasks
```sql
-- Vacuum and analyze
VACUUM ANALYZE;

-- Check table bloat
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexrelname NOT LIKE 'pg_toast%'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Backup and Restore

### Manual Backup
```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier <instance-id> \
  --db-snapshot-identifier manual-backup-$(date +%Y%m%d-%H%M%S)

# Wait for completion
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier manual-backup-<id>

# Verify snapshot
aws rds describe-db-snapshots \
  --db-snapshot-identifier manual-backup-<id>
```

### Restore from Backup
```bash
# Restore to new instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier restored-db \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.r6g.xlarge

# Wait for availability
aws rds wait db-instance-available \
  --db-instance-identifier restored-db

# Test connection
psql -h <restored-endpoint> -U <user> -d <database>
```

## Performance Tuning

### Query Optimization
```sql
-- Find slow queries
SELECT pid, now() - pg_stat_activity.query_start AS duration,
  query, state
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - pg_stat_activity.query_start > interval '5 seconds'
ORDER BY duration DESC;

-- Explain query plan
EXPLAIN ANALYZE SELECT ...;

-- Create index
CREATE INDEX CONCURRENTLY idx_name ON table(column);
```

### Parameter Tuning
```bash
# Modify parameter group
aws rds modify-db-parameter-group \
  --db-parameter-group-name <name> \
  --parameters \
    "ParameterName=max_connections,ParameterValue=500,ApplyMethod=immediate" \
    "ParameterName=shared_buffers,ParameterValue={DBInstanceClassMemory/4},ApplyMethod=pending-reboot"

# Reboot if needed
aws rds reboot-db-instance --db-instance-identifier <instance-id>
```

## Storage Management

### Increase Storage
```bash
# Modify storage
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --allocated-storage 1000 \
  --storage-type gp3 \
  --apply-immediately

# Monitor modification
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].[DBInstanceStatus,AllocatedStorage,StorageType]'
```

## Version Upgrades

### Minor Version Upgrade
```bash
# List available versions
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 14.7 \
  --query 'DBEngineVersions[*].ValidUpgradeTarget[*].EngineVersion'

# Upgrade
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --engine-version 14.9 \
  --apply-immediately \
  --allow-major-version-upgrade false
```

### Major Version Upgrade
```bash
# Test on read replica first
# Then upgrade primary

# Create manual snapshot first
aws rds create-db-snapshot \
  --db-instance-identifier <instance-id> \
  --db-snapshot-identifier pre-upgrade-$(date +%Y%m%d)

# Upgrade
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --engine-version 15.2 \
  --allow-major-version-upgrade \
  --apply-immediately
```

## Monitoring

### Key Metrics
```bash
# CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average

# Storage
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --period 300 \
  --statistics Average

# IOPS
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReadIOPS \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --period 300 \
  --statistics Sum
```

## Troubleshooting

### Connection Issues
```bash
# Check security groups
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].VpcSecurityGroups'

# Test connectivity
telnet <endpoint> 5432

# Check parameter group
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].DBParameterGroups'
```

### Performance Issues
```sql
-- Check locks
SELECT pid, usename, pg_blocking_pids(pid) as blocked_by, query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

-- Kill blocking query
SELECT pg_terminate_backend(<pid>);

-- Check cache hit ratio
SELECT sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;
```
