# IDP Operational Runbooks

## Table of Contents
1. [Deployment Procedures](#deployment-procedures)
2. [Incident Response](#incident-response)
3. [Disaster Recovery](#disaster-recovery)
4. [Monitoring & Alerting](#monitoring--alerting)
5. [Scaling Operations](#scaling-operations)
6. [Security Operations](#security-operations)
7. [Cost Management](#cost-management)

---

## Deployment Procedures

### Blue-Green Deployment

**Prerequisites:**
- Verify both blue and green environments are healthy
- Ensure database migration scripts are ready
- Confirm rollback plan is documented

**Steps:**

1. **Prepare Green Environment**
```bash
# Deploy to green environment
kubectl apply -f deployments/green/ -n idp-green

# Verify deployment
kubectl rollout status deployment/api-gateway -n idp-green
kubectl get pods -n idp-green
```

2. **Run Smoke Tests**
```bash
# Execute smoke test suite
./scripts/smoke-tests.sh --environment green --endpoint https://green.idp.example.com

# Verify critical paths
curl -X GET https://green.idp.example.com/health
curl -X POST https://green.idp.example.com/api/v1/test
```

3. **Gradual Traffic Shift**
```bash
# Shift 10% traffic to green
aws elbv2 modify-target-group-attributes \
  --target-group-arn $GREEN_TG_ARN \
  --attributes Key=stickiness.enabled,Value=true

aws elbv2 modify-rule \
  --rule-arn $ROUTING_RULE_ARN \
  --conditions Field=path-pattern,Values="/*" \
  --actions Type=forward,ForwardConfig='{
    "TargetGroups":[
      {"TargetGroupArn":"'$BLUE_TG_ARN'","Weight":90},
      {"TargetGroupArn":"'$GREEN_TG_ARN'","Weight":10}
    ]
  }'

# Monitor for 10 minutes
watch -n 30 'kubectl top pods -n idp-green'

# Increase to 50%
aws elbv2 modify-rule \
  --rule-arn $ROUTING_RULE_ARN \
  --actions Type=forward,ForwardConfig='{
    "TargetGroups":[
      {"TargetGroupArn":"'$BLUE_TG_ARN'","Weight":50},
      {"TargetGroupArn":"'$GREEN_TG_ARN'","Weight":50}
    ]
  }'

# Final shift to 100%
aws elbv2 modify-rule \
  --rule-arn $ROUTING_RULE_ARN \
  --actions Type=forward,ForwardConfig='{
    "TargetGroups":[
      {"TargetGroupArn":"'$GREEN_TG_ARN'","Weight":100}
    ]
  }'
```

4. **Validation**
```bash
# Check error rates
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=$ALB_NAME \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Verify application metrics
kubectl exec -it prometheus-0 -n monitoring -- \
  promtool query instant http://localhost:9090 \
  'rate(http_requests_total{status=~"5.."}[5m])'
```

5. **Rollback (if needed)**
```bash
# Immediate rollback to blue
aws elbv2 modify-rule \
  --rule-arn $ROUTING_RULE_ARN \
  --actions Type=forward,ForwardConfig='{
    "TargetGroups":[
      {"TargetGroupArn":"'$BLUE_TG_ARN'","Weight":100}
    ]
  }'

# Scale down green environment
kubectl scale deployment --all --replicas=0 -n idp-green
```

### Canary Deployment

**Steps:**

1. **Deploy Canary Version**
```bash
# Apply canary deployment
kubectl apply -f deployments/canary/deployment.yaml

# Create canary service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-canary
  namespace: idp-prod
spec:
  selector:
    app: api-gateway
    version: canary
  ports:
    - port: 80
      targetPort: 8080
EOF
```

2. **Configure Traffic Split**
```bash
# Using Istio for traffic management
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: idp-prod
spec:
  hosts:
    - api-gateway
  http:
    - match:
        - headers:
            canary:
              exact: "true"
      route:
        - destination:
            host: api-gateway-canary
            port:
              number: 80
          weight: 100
    - route:
        - destination:
            host: api-gateway
            port:
              number: 80
          weight: 95
        - destination:
            host: api-gateway-canary
            port:
              number: 80
          weight: 5
EOF
```

3. **Monitor Canary Metrics**
```bash
# Watch canary metrics
watch -n 10 'kubectl exec -it prometheus-0 -n monitoring -- \
  promtool query instant http://localhost:9090 \
  "sum(rate(http_requests_total{version=\"canary\"}[5m])) by (status)"'
```

---

## Incident Response

### Severity Level Classification

| Severity | Definition | Response Time | Escalation |
|----------|-----------|---------------|------------|
| SEV1 | Complete platform outage | 5 minutes | CTO + VP Engineering |
| SEV2 | Major feature unavailable | 15 minutes | Engineering Manager |
| SEV3 | Minor feature degradation | 1 hour | Team Lead |
| SEV4 | Non-critical issue | 4 hours | On-call Engineer |

### SEV1 Incident Response Playbook

**Initial Response (0-5 minutes)**

1. **Acknowledge Alert**
```bash
# Acknowledge in PagerDuty
pd-cli incident acknowledge -i $INCIDENT_ID

# Join war room
slack-cli join-channel #incident-$INCIDENT_ID
```

2. **Initial Assessment**
```bash
# Check system status
./scripts/health-check.sh --all

# Review recent deployments
kubectl rollout history deployment --all-namespaces | grep -v "No rollout"

# Check AWS service health
aws health describe-events --region us-east-1
```

3. **Establish War Room**
```bash
# Create incident channel
slack-cli create-channel incident-$(date +%Y%m%d-%H%M)

# Post initial status
slack-cli post "SEV1 Incident Declared
- Time: $(date)
- Impact: [Describe impact]
- Current Status: Investigating
- IC: @oncall-engineer
- Slack Channel: #incident-$(date +%Y%m%d-%H%M)"
```

**Mitigation (5-30 minutes)**

1. **Implement Immediate Fixes**
```bash
# Scale up resources if needed
kubectl scale deployment api-gateway --replicas=10 -n idp-prod

# Restart problematic pods
kubectl rollout restart deployment/api-gateway -n idp-prod

# Enable circuit breaker
kubectl patch configmap api-config -n idp-prod \
  --type merge -p '{"data":{"circuit_breaker":"enabled"}}'
```

2. **Failover if Necessary**
```bash
# Trigger regional failover
aws lambda invoke \
  --function-name idp-failover-orchestrator \
  --payload '{"action":"failover","target":"secondary"}' \
  response.json

# Update DNS
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file://failover-dns.json
```

**Resolution (30+ minutes)**

1. **Root Cause Analysis**
```bash
# Collect logs
kubectl logs -l app=api-gateway --since=1h -n idp-prod > incident-logs.txt

# Get metrics
aws cloudwatch get-metric-statistics \
  --namespace IDP/Application \
  --metric-name ErrorRate \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average > metrics.json
```

2. **Document Incident**
```markdown
# Incident Report Template

## Incident ID: INC-YYYYMMDD-001

### Summary
- **Date/Time**: YYYY-MM-DD HH:MM UTC
- **Duration**: X minutes
- **Severity**: SEV1
- **Services Affected**: [List services]

### Timeline
- HH:MM - Alert triggered
- HH:MM - Engineer acknowledged
- HH:MM - Root cause identified
- HH:MM - Mitigation applied
- HH:MM - Service restored

### Root Cause
[Detailed explanation]

### Resolution
[Steps taken to resolve]

### Action Items
- [ ] Fix root cause
- [ ] Update monitoring
- [ ] Update runbooks
- [ ] Schedule post-mortem
```

---

## Disaster Recovery

### Regional Failover Procedure

**Pre-Failover Checks**

```bash
# Verify secondary region health
aws elbv2 describe-target-health \
  --target-group-arn $SECONDARY_TG_ARN \
  --region eu-west-1

# Check database replication lag
aws rds describe-db-clusters \
  --db-cluster-identifier idp-aurora-secondary \
  --region eu-west-1 \
  --query 'DBClusters[0].ReplicationSourceIdentifier'

# Verify data sync status
aws s3api head-bucket --bucket idp-backup-eu-west-1
```

**Execute Failover**

1. **Database Failover**
```bash
# Promote read replica to primary
aws rds promote-read-replica-db-cluster \
  --db-cluster-identifier idp-aurora-secondary \
  --region eu-west-1

# Wait for promotion
aws rds wait db-cluster-available \
  --db-cluster-identifier idp-aurora-secondary \
  --region eu-west-1
```

2. **Application Failover**
```bash
# Scale up secondary region
kubectl scale deployment --all --replicas=5 -n idp-prod \
  --context eks-eu-west-1

# Update service discovery
aws servicediscovery update-service \
  --id $SERVICE_ID \
  --service '{
    "DnsConfig": {
      "DnsRecords": [{
        "Type": "A",
        "TTL": 60
      }]
    }
  }'
```

3. **DNS Failover**
```bash
# Update Route53 records
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.idp.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{
          "Value": "eu-west-1-alb.amazonaws.com"
        }]
      }
    }]
  }'
```

### Backup and Restore Procedures

**Automated Backup Verification**

```bash
#!/bin/bash
# backup-verification.sh

# Test database backup
aws backup start-restore-job \
  --recovery-point-arn $RECOVERY_POINT_ARN \
  --metadata "test-restore" \
  --iam-role-arn $BACKUP_ROLE_ARN \
  --resource-type RDS

# Test S3 backup
aws s3 sync s3://idp-backup-primary/latest/ /tmp/backup-test/ --dryrun

# Verify backup integrity
aws backup describe-recovery-point \
  --backup-vault-name idp-vault-primary \
  --recovery-point-arn $RECOVERY_POINT_ARN
```

**Point-in-Time Recovery**

```bash
# Restore database to specific time
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier idp-aurora-primary \
  --db-cluster-identifier idp-aurora-pitr-$(date +%Y%m%d) \
  --restore-to-time "2024-01-15T03:30:00.000Z"

# Restore S3 objects
aws s3api list-object-versions \
  --bucket idp-data \
  --prefix critical/ \
  --query 'Versions[?LastModified>=`2024-01-15`]'
```

---

## Monitoring & Alerting

### Key Metrics and Thresholds

```yaml
# monitoring-config.yaml
metrics:
  application:
    - name: api_latency_p99
      threshold: 1000ms
      window: 5m
      severity: warning
    
    - name: error_rate
      threshold: 1%
      window: 5m
      severity: critical
    
    - name: request_rate
      threshold: 10000/s
      window: 1m
      severity: info
  
  infrastructure:
    - name: cpu_utilization
      threshold: 80%
      window: 5m
      severity: warning
    
    - name: memory_utilization
      threshold: 90%
      window: 5m
      severity: critical
    
    - name: disk_utilization
      threshold: 85%
      window: 10m
      severity: warning
  
  database:
    - name: connection_count
      threshold: 80%
      window: 5m
      severity: warning
    
    - name: replication_lag
      threshold: 1000ms
      window: 1m
      severity: critical
```

### Custom Alerts Configuration

```bash
# Create CloudWatch alarm
aws cloudwatch put-metric-alarm \
  --alarm-name idp-high-error-rate \
  --alarm-description "Alert when error rate exceeds 1%" \
  --metric-name 4XXError \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 300 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:us-east-1:123456789012:idp-alerts

# Create Prometheus alert
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: idp-alerts
  namespace: monitoring
spec:
  groups:
    - name: application
      rules:
        - alert: HighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High error rate detected"
            description: "Error rate is {{ \$value }} errors per second"
EOF
```

---

## Scaling Operations

### Manual Scaling Procedures

```bash
# Scale EKS nodes
aws eks update-nodegroup-config \
  --cluster-name idp-cluster \
  --nodegroup-name idp-workers \
  --scaling-config minSize=5,maxSize=50,desiredSize=10

# Scale RDS read replicas
aws rds create-db-instance-read-replica \
  --db-instance-identifier idp-aurora-replica-$(date +%s) \
  --source-db-instance-identifier idp-aurora-primary

# Scale ElastiCache
aws elasticache modify-replication-group \
  --replication-group-id idp-redis \
  --apply-immediately \
  --node-groups-to-add "NodeGroupId=0002,PrimaryAvailabilityZone=us-east-1b,ReplicaAvailabilityZones=us-east-1c"
```

### Auto-scaling Tuning

```bash
# Adjust HPA settings
kubectl patch hpa api-gateway-hpa -n idp-prod \
  --type merge \
  -p '{"spec":{"maxReplicas":100,"targetCPUUtilizationPercentage":60}}'

# Update cluster autoscaler
kubectl set env deployment/cluster-autoscaler \
  -n kube-system \
  SCALE_DOWN_DELAY_AFTER_ADD=5m \
  SCALE_DOWN_UNNEEDED_TIME=5m
```

---

## Security Operations

### Security Incident Response

```bash
# Isolate compromised resource
aws ec2 modify-instance-attribute \
  --instance-id i-1234567890abcdef0 \
  --no-source-dest-check

aws ec2 modify-network-interface-attribute \
  --network-interface-id eni-12345 \
  --groups sg-isolation

# Capture forensic data
aws ec2 create-snapshot \
  --volume-id vol-12345 \
  --description "Forensic snapshot $(date)"

# Rotate credentials
aws iam create-access-key --user-name suspected-user
aws iam delete-access-key --access-key-id AKIA... --user-name suspected-user

# Enable enhanced monitoring
aws guardduty update-detector \
  --detector-id 12abc34d567e8fa901bc2d34e56789f0 \
  --finding-publishing-frequency FIFTEEN_MINUTES
```

### Compliance Checks

```bash
# Run AWS Config compliance check
aws configservice start-config-rules-evaluation \
  --config-rule-names $(aws configservice describe-config-rules \
    --query 'ConfigRules[].ConfigRuleName' \
    --output text)

# Security scan
prowler -g cis_level2

# Vulnerability scan
trivy image --severity HIGH,CRITICAL idp-api:latest
```

---

## Cost Management

### Cost Monitoring

```bash
# Generate cost report
python3 /opt/idp/scripts/cost-optimization-report.py \
  --profile production \
  --output /tmp/cost-report-$(date +%Y%m).html

# Check current month spend
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Resource Cleanup

```bash
# Find and delete unused resources
# Unattached EBS volumes
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].VolumeId' --output text | \
  xargs -n1 aws ec2 delete-volume --volume-id

# Old snapshots
aws ec2 describe-snapshots --owner-ids self \
  --query "Snapshots[?StartTime<='$(date -d '90 days ago' --iso-8601)'].SnapshotId" \
  --output text | xargs -n1 aws ec2 delete-snapshot --snapshot-id

# Unused Elastic IPs
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId' \
  --output text | xargs -n1 aws ec2 release-address --allocation-id
```

---

## Maintenance Windows

### Planned Maintenance Procedure

```bash
# Pre-maintenance checklist
./scripts/pre-maintenance-check.sh

# Enable maintenance mode
kubectl patch configmap app-config -n idp-prod \
  --type merge -p '{"data":{"maintenance_mode":"true"}}'

# Perform maintenance tasks
# ... database updates, patches, etc ...

# Disable maintenance mode
kubectl patch configmap app-config -n idp-prod \
  --type merge -p '{"data":{"maintenance_mode":"false"}}'

# Post-maintenance validation
./scripts/post-maintenance-validation.sh
```

---

## Communication Templates

### Incident Communication

```markdown
**Initial Alert**
🚨 SERVICE DISRUPTION ALERT

We are currently experiencing issues with the IDP platform.
- Impact: [Brief description]
- Status: Investigating
- Next Update: In 15 minutes

**Update**
📊 SERVICE DISRUPTION UPDATE

- Current Status: Mitigation in progress
- Root Cause: [If known]
- ETA for Resolution: [Time estimate]
- Workaround: [If available]

**Resolution**
✅ SERVICE RESTORED

The IDP platform has been fully restored.
- Duration: [Time]
- Root Cause: [Brief explanation]
- Next Steps: Post-mortem scheduled for [Date/Time]
```

---

## Automation Scripts Location

All operational scripts are located in:
- `/opt/idp/scripts/` - Production scripts
- `/opt/idp/runbooks/` - Detailed runbooks
- `/opt/idp/monitoring/` - Monitoring configurations
- `/opt/idp/terraform/` - Infrastructure as Code

## Contact Information

- **On-Call**: PagerDuty - idp-oncall
- **Slack**: #idp-operations
- **Email**: idp-team@example.com
- **Wiki**: https://wiki.example.com/idp