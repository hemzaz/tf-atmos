# Troubleshooting Guide

## Common Issues and Resolutions

### 1. High Pod CPU Usage

**Symptoms:**
- Pods showing high CPU in `kubectl top`
- Application slow response times
- HPA scaling up frequently

**Investigation:**
```bash
# Check CPU usage
kubectl top pods -n <namespace>

# Check resource limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 Limits

# Profile application (if tooling available)
kubectl exec -it <pod-name> -n <namespace> -- curl localhost:6060/debug/pprof/profile?seconds=30 > cpu.prof
```

**Resolution:**
```bash
# Increase CPU limits
kubectl set resources deployment/<name> -n <namespace> \
  --limits=cpu=2000m --requests=cpu=1000m

# OR optimize application code
# OR add more replicas
kubectl scale deployment/<name> -n <namespace> --replicas=<higher-count>
```

### 2. Database Connection Pool Exhaustion

**Symptoms:**
- "Too many connections" errors
- Application timeouts
- Database CPU normal but connections maxed

**Investigation:**
```bash
# Check RDS connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum

# Check active connections
psql -h <host> -U <user> -c "
  SELECT count(*) FROM pg_stat_activity;
  SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
"
```

**Resolution:**
```bash
# Kill idle connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND state_change < NOW() - INTERVAL '10 minutes';

# Increase max_connections
aws rds modify-db-parameter-group \
  --db-parameter-group-name <name> \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=immediate"

# Optimize application connection pooling
# Set max_pool_size, max_overflow, pool_timeout
```

### 3. Pod CrashLoopBackOff

**Symptoms:**
- Pod repeatedly restarting
- Status shows CrashLoopBackOff
- Application not accessible

**Investigation:**
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check current logs
kubectl logs <pod-name> -n <namespace>

# Check previous logs
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
```

**Common Causes & Resolutions:**
```bash
# OOMKilled - Increase memory
kubectl set resources deployment/<name> -n <namespace> \
  --limits=memory=2Gi --requests=memory=1Gi

# Missing ConfigMap/Secret
kubectl get configmap -n <namespace>
kubectl apply -f missing-config.yaml

# Application startup failure
# Fix application code or configuration

# Liveness probe failing
kubectl patch deployment <name> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds", "value":60}]'
```

### 4. Service Unreachable

**Symptoms:**
- Cannot access service via DNS/IP
- Connection timeouts
- 503 Service Unavailable

**Investigation:**
```bash
# Check service
kubectl get svc <service-name> -n <namespace>

# Check endpoints
kubectl get endpoints <service-name> -n <namespace>

# Check ingress
kubectl get ingress -n <namespace>

# Check pods
kubectl get pods -n <namespace> -l app=<name>

# Test from within cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
# Inside pod:
wget -O- http://<service-name>.<namespace>.svc.cluster.local/health
```

**Resolution:**
```bash
# If no endpoints, pods not matching selector
kubectl get svc <service-name> -n <namespace> -o yaml | grep selector

# Fix pod labels
kubectl label pod <pod-name> -n <namespace> app=<name> --overwrite

# If ingress issue, check ALB
aws elbv2 describe-target-health --target-group-arn <arn>
```

### 5. Slow Database Queries

**Symptoms:**
- High database CPU
- Slow API responses
- Query timeout errors

**Investigation:**
```bash
# Check slow queries (PostgreSQL)
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - pg_stat_activity.query_start > interval '5 seconds'
ORDER BY duration DESC;

# Enable slow query log
aws rds modify-db-parameter-group \
  --db-parameter-group-name <name> \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"

# Check for missing indexes
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE schemaname = 'public'
ORDER BY abs(correlation) DESC;
```

**Resolution:**
```sql
-- Add missing indexes
CREATE INDEX CONCURRENTLY idx_table_column ON table(column);

-- Analyze tables
ANALYZE table_name;

-- Update statistics
VACUUM ANALYZE;

-- Kill long-running query
SELECT pg_terminate_backend(<pid>);
```

### 6. Disk Space Full

**Symptoms:**
- "No space left on device" errors
- Pod evictions
- Write operations failing

**Investigation:**
```bash
# Check node disk usage
kubectl top nodes

# Check pod disk usage
kubectl exec -it <pod-name> -n <namespace> -- df -h

# Find large files
kubectl exec -it <pod-name> -n <namespace> -- du -sh /* | sort -hr | head -10

# Check PVC usage
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
```

**Resolution:**
```bash
# Clean up logs
kubectl exec -it <pod-name> -n <namespace> -- find /var/log -name "*.log" -mtime +7 -delete

# Increase PVC size
kubectl patch pvc <pvc-name> -n <namespace> \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Add log rotation
# Update application logging configuration

# Clean old Docker images (on nodes)
docker image prune -a -f
```

## Quick Diagnostic Commands

```bash
# Cluster health
kubectl get nodes
kubectl get componentstatuses

# Resource usage
kubectl top nodes
kubectl top pods -A

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Failed pods
kubectl get pods -A --field-selector=status.phase=Failed

# Pending pods
kubectl get pods -A --field-selector=status.phase=Pending

# CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM

# RDS status
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'

# ELB health
aws elbv2 describe-target-health --target-group-arn <arn>
```

## Performance Bottleneck Checklist

- [ ] Check application logs for errors
- [ ] Check resource utilization (CPU, memory, disk)
- [ ] Check database performance
- [ ] Check network connectivity
- [ ] Check external dependencies
- [ ] Check recent deployments
- [ ] Check CloudWatch metrics
- [ ] Review recent changes (Git, CloudTrail)
