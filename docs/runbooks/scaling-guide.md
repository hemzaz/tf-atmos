# Scaling Guide

## Kubernetes Workloads

### Manual Scaling
```bash
# Scale deployment
kubectl scale deployment/<name> -n <namespace> --replicas=<count>

# Scale StatefulSet
kubectl scale statefulset/<name> -n <namespace> --replicas=<count>
```

### Horizontal Pod Autoscaler (HPA)
```bash
# Create HPA
kubectl autoscale deployment <name> -n <namespace> \
  --cpu-percent=70 --min=3 --max=10

# Check HPA status
kubectl get hpa -n <namespace>
```

## EKS Cluster Scaling

### Node Group Scaling
```bash
# Update node group size
aws eks update-nodegroup-config \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --scaling-config minSize=3,maxSize=10,desiredSize=5
```

### Cluster Autoscaler
- Monitors pod resource requests
- Automatically adds/removes nodes
- Configure min/max nodes in ASG

## RDS Scaling

### Vertical Scaling
```bash
# Modify instance class
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --db-instance-class db.r6g.xlarge \
  --apply-immediately

# Monitor modification
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].DBInstanceStatus'
```

### Read Replicas
```bash
# Create read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier <replica-id> \
  --source-db-instance-identifier <source-id> \
  --db-instance-class db.r6g.large
```

### Storage Scaling
```bash
# Increase storage
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --allocated-storage 500 \
  --apply-immediately
```

## ElastiCache Scaling

### Add Cache Nodes
```bash
aws elasticache modify-replication-group \
  --replication-group-id <group-id> \
  --num-cache-clusters 5 \
  --apply-immediately
```

## Load Balancer Scaling

ALB scales automatically based on traffic patterns. Monitor:
- Active connections
- Request count
- Target response time

## Capacity Planning

### Resource Utilization Targets
- CPU: 60-70% (allows burst capacity)
- Memory: 70-80%
- Disk: < 80%
- Network: < 70% of bandwidth

### When to Scale

**Scale UP if:**
- CPU > 70% for 10+ minutes
- Memory > 80% sustained
- Request latency P95 > SLO
- Error rate increasing

**Scale DOWN if:**
- CPU < 30% for 2+ hours
- Memory < 50% sustained
- Over-provisioned capacity
- Cost optimization opportunity
