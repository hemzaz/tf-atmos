# Rollback Procedures

## Overview

Emergency procedures for rolling back deployments when issues are detected.

## Decision Matrix

| Issue | Severity | Action | Timeline |
|-------|----------|--------|----------|
| Complete outage | P0 | Immediate rollback | < 5 min |
| Major errors (>5%) | P1 | Rollback after confirmation | < 15 min |
| Performance degradation (>50%) | P1 | Rollback after investigation | < 30 min |
| Minor errors (<1%) | P2 | Monitor, rollback if escalates | < 2 hours |
| Cosmetic issues | P3 | Fix forward | Next deployment |

## Kubernetes Application Rollback

### Method 1: Rollback Last Deployment

```bash
# Immediate rollback to previous version
kubectl rollout undo deployment/<name> -n <namespace>

# Watch rollback progress
kubectl rollout status deployment/<name> -n <namespace>

# Verify pods are running
kubectl get pods -n <namespace> -l app=<name>

# Check logs
kubectl logs -n <namespace> -l app=<name> --tail=100
```

### Method 2: Rollback to Specific Revision

```bash
# View revision history
kubectl rollout history deployment/<name> -n <namespace>

# View specific revision details
kubectl rollout history deployment/<name> -n <namespace> --revision=<number>

# Rollback to specific revision
kubectl rollout undo deployment/<name> -n <namespace> --to-revision=<number>

# Verify rollback
kubectl rollout status deployment/<name> -n <namespace>
```

### Method 3: Helm Rollback

```bash
# List release history
helm history <release-name> -n <namespace>

# Rollback to previous release
helm rollback <release-name> -n <namespace>

# Rollback to specific revision
helm rollback <release-name> <revision> -n <namespace>

# Wait for rollback to complete
helm status <release-name> -n <namespace>
```

## Terraform Infrastructure Rollback

### Method 1: Revert Git Commit

```bash
# Find the last good commit
git log --oneline --decorate | head -n 10

# Revert to last good state
git revert <bad-commit-hash>

# OR reset (if not pushed to main)
git reset --hard <last-good-commit>

# Plan changes
atmos terraform plan <component> -s <stack>

# Apply rollback
atmos terraform apply <component> -s <stack>
```

### Method 2: Terraform State Manipulation

```bash
# WARNING: Use with extreme caution

# List resources in state
atmos terraform state list <component> -s <stack>

# Import previous resource configuration
atmos terraform import <component> -s <stack> \
  <resource-type>.<resource-name> <resource-id>

# Apply previous configuration
atmos terraform apply <component> -s <stack>
```

### Method 3: Restore from Backup

```bash
# List available state backups
ls -lah .terraform/*.backup

# Copy backup to current state
cp terraform.tfstate.backup terraform.tfstate

# Verify state
atmos terraform show <component> -s <stack>

# Plan and apply
atmos terraform plan <component> -s <stack>
atmos terraform apply <component> -s <stack>
```

## Database Rollback

### Rollback Migration

```bash
# Method 1: Use migration tool rollback
kubectl exec -it <pod-name> -n <namespace> -- \
  python manage.py migrate <app> <previous-migration>

# Method 2: Flyway undo
flyway -url=<jdbc-url> -user=<user> -password=<password> undo

# Method 3: Manual SQL rollback
psql -h <host> -U <user> -d <database> -f rollback.sql
```

### Restore from Snapshot

```bash
# List recent snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier <instance-id> \
  --query 'reverse(sort_by(DBSnapshots,&SnapshotCreateTime))[:5]' \
  --output table

# Restore from snapshot (creates new instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <new-instance-id> \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class <instance-class> \
  --vpc-security-group-ids <security-group-ids> \
  --db-subnet-group-name <subnet-group>

# Wait for restoration
aws rds wait db-instance-available \
  --db-instance-identifier <new-instance-id>

# Update application to use new endpoint
kubectl set env deployment/<name> -n <namespace> \
  DATABASE_HOST=<new-endpoint>
```

### Point-in-Time Recovery

```bash
# Restore to specific time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier <source-id> \
  --target-db-instance-identifier <target-id> \
  --restore-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)

# Monitor restore progress
aws rds describe-db-instances \
  --db-instance-identifier <target-id> \
  --query 'DBInstances[0].DBInstanceStatus'
```

## Lambda Function Rollback

### Rollback to Previous Version

```bash
# List function versions
aws lambda list-versions-by-function \
  --function-name <function-name> \
  --query 'Versions[*].[Version,LastModified]' \
  --output table

# Update alias to previous version
aws lambda update-alias \
  --function-name <function-name> \
  --name production \
  --function-version <previous-version>

# Verify rollback
aws lambda get-alias \
  --function-name <function-name> \
  --name production
```

## Load Balancer / Traffic Rollback

### Blue-Green Rollback

```bash
# Switch traffic back to blue (previous version)
kubectl patch service app-service -n <namespace> \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# Scale up blue if scaled down
kubectl scale deployment app-blue -n <namespace> --replicas=<original-count>

# Monitor metrics
kubectl get pods -n <namespace> -l version=blue
```

### Canary Rollback

```bash
# Remove canary traffic routing
kubectl patch ingress <name> -n <namespace> \
  --type=json -p='[{"op":"remove","path":"/spec/rules/0/http/paths/0/backend/canary"}]'

# Delete canary deployment
kubectl delete deployment app-canary -n <namespace>

# Verify all traffic on stable
kubectl get svc <service-name> -n <namespace> -o yaml
```

## Configuration Rollback

### ConfigMap Rollback

```bash
# Get previous ConfigMap version
kubectl get configmap <name> -n <namespace> -o yaml > current-configmap.yaml

# Apply previous version
kubectl apply -f previous-configmap.yaml -n <namespace>

# Restart pods to pick up new config
kubectl rollout restart deployment/<name> -n <namespace>
```

### Secrets Rollback

```bash
# Restore secret from backup
kubectl apply -f secret-backup.yaml -n <namespace>

# OR restore from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id <secret-id> \
  --version-stage AWSPREVIOUS \
  --query SecretString \
  --output text | kubectl apply -f -

# Restart affected pods
kubectl rollout restart deployment/<name> -n <namespace>
```

## DNS Rollback

### Route53 Rollback

```bash
# Get current record set
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='<domain>']"

# Create change batch for rollback
cat > change-batch.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "<domain>",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "<previous-ip>"}]
    }
  }]
}
EOF

# Apply change
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://change-batch.json

# Wait for propagation (check TTL)
```

## Verification After Rollback

### Application Health

```bash
# 1. Check health endpoints
curl -f https://<domain>/health || echo "Health check failed"

# 2. Check error rates
kubectl logs -n <namespace> -l app=<name> --tail=100 | grep -c ERROR

# 3. Check response times
time curl -s https://<domain>/api/endpoint > /dev/null

# 4. Check pod status
kubectl get pods -n <namespace> -l app=<name>

# 5. Verify CloudWatch alarms
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].AlarmName' \
  --output text
```

### Database Verification

```bash
# Connect and verify data integrity
psql -h <host> -U <user> -d <database> -c "
  SELECT COUNT(*) FROM critical_table;
  SELECT MAX(created_at) FROM critical_table;
  SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1;
"

# Check replication lag (if applicable)
aws rds describe-db-instances \
  --db-instance-identifier <replica-id> \
  --query 'DBInstances[0].ReadReplicaDBInstanceIdentifiers'
```

### Infrastructure Verification

```bash
# Verify Terraform state matches deployed resources
atmos terraform plan <component> -s <stack>

# Check for configuration drift
terraform show

# Verify resource tags
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=production \
  --resource-type-filters ec2 rds
```

## Communication

### Rollback Announcement Template

```markdown
**🔴 ROLLBACK IN PROGRESS**

**Environment:** Production
**Reason:** [Brief description of issue]
**Rollback Target:** [Previous version/revision]
**Expected Duration:** ~15 minutes
**Impact:** [Description]

**Action Items:**
- Initiating rollback now
- Monitoring metrics
- Will provide update in 15 minutes

**Incident Commander:** [Name]
```

### Rollback Complete Template

```markdown
**✅ ROLLBACK COMPLETE**

**Duration:** X minutes
**Status:** Services restored
**Current Version:** [Version]

**Verification:**
- Health checks: ✅ Passing
- Error rate: 0.1%
- Latency: Normal
- All alarms: Clear

**Next Steps:**
- Root cause analysis scheduled
- Fix will be deployed after thorough testing
- Postmortem meeting: [Date/Time]
```

## Post-Rollback Actions

1. **Immediate (Within 1 hour):**
   - Verify all systems operational
   - Document rollback steps taken
   - Update status page
   - Notify stakeholders

2. **Short-term (Within 24 hours):**
   - Conduct root cause analysis
   - Create bug report with details
   - Update runbooks if needed
   - Schedule postmortem

3. **Medium-term (Within 1 week):**
   - Implement fix with thorough testing
   - Add regression tests
   - Review deployment process
   - Update documentation

## Rollback Checklist

- [ ] Incident severity assessed
- [ ] Incident commander assigned
- [ ] Stakeholders notified
- [ ] Rollback command executed
- [ ] Rollback progress monitored
- [ ] Health checks passed
- [ ] Metrics returned to normal
- [ ] Alarms cleared
- [ ] Status page updated
- [ ] Team notified
- [ ] Rollback documented
- [ ] Postmortem scheduled

## Common Issues

### Rollback Failed

```bash
# If rollback fails, try:

# 1. Force pod restart
kubectl delete pods -n <namespace> -l app=<name>

# 2. Scale to zero and back
kubectl scale deployment/<name> -n <namespace> --replicas=0
sleep 10
kubectl scale deployment/<name> -n <namespace> --replicas=<original-count>

# 3. Delete and recreate deployment
kubectl delete deployment/<name> -n <namespace>
kubectl apply -f previous-deployment.yaml
```

### Database Rollback Conflicts

```bash
# If migration rollback fails:

# 1. Check current schema version
SELECT version FROM schema_migrations;

# 2. Manually update schema_migrations table
DELETE FROM schema_migrations WHERE version = '<bad-migration>';

# 3. Apply rollback SQL manually
psql -f manual-rollback.sql

# 4. Verify data integrity
# Run data validation queries
```

## References

- [Deployment Procedures](/docs/runbooks/deployment-procedures.md)
- [Incident Response](/docs/runbooks/incident-response.md)
- [Database Maintenance](/docs/runbooks/database-maintenance.md)
