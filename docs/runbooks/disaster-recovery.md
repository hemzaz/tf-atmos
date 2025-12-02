# Disaster Recovery Runbook

## Recovery Objectives

- **RPO (Recovery Point Objective):** 24 hours
- **RTO (Recovery Time Objective):** 4 hours

## DR Scenarios

### Scenario 1: Region Failure

**Detection:**
- Multiple AWS service outages
- Unable to reach resources in primary region
- AWS Health Dashboard shows regional issues

**Recovery Steps:**

```bash
# 1. Activate DR plan
# 2. Notify team via alternate communication channel

# 3. Promote secondary region database
aws rds promote-read-replica \
  --db-instance-identifier <dr-instance-id> \
  --region us-west-2

# 4. Update DNS to DR region
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://dr-dns-change.json

# 5. Scale up DR environment
kubectl scale deployment <name> -n <namespace> \
  --replicas=<production-count>

# 6. Update configuration for DR region
kubectl set env deployment/<name> -n <namespace> \
  AWS_REGION=us-west-2

# 7. Verify application functionality
curl https://<domain>/health

# 8. Monitor metrics in DR region
```

**Estimated Recovery Time:** 2-3 hours

### Scenario 2: Data Corruption

**Detection:**
- Integrity check failures
- User reports of missing/incorrect data
- Application errors related to data

**Recovery Steps:**

```bash
# 1. Identify corruption scope and time
# 2. Stop writes to affected database

# 3. Restore from backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier restored-db \
  --db-snapshot-identifier <snapshot-before-corruption>

# 4. Verify restored data
psql -h <restored-endpoint> -U <user> -d <database> -c "
  SELECT COUNT(*) FROM critical_table;
  SELECT MAX(created_at) FROM critical_table;
"

# 5. Export uncorrupted data
pg_dump -h <restored-endpoint> -U <user> <database> > backup.sql

# 6. Merge with production (carefully)
# 7. Resume normal operations
```

**Estimated Recovery Time:** 4-6 hours

### Scenario 3: Complete Account Compromise

**Detection:**
- Unauthorized IAM changes
- Unexpected resource deletions
- GuardDuty HIGH/CRITICAL findings

**Recovery Steps:**

```bash
# 1. Contact AWS Support immediately
# 2. Rotate all credentials

# 3. Restore infrastructure from Terraform
cd stacks/deployments/<tenant>/<account>/<environment>
atmos terraform plan <component> -s <stack>
atmos terraform apply <component> -s <stack>

# 4. Restore data from backups
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --metadata DBInstanceIdentifier=restored-db

# 5. Review CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteUser \
  --max-items 100

# 6. Implement additional security controls
```

**Estimated Recovery Time:** 8-12 hours

## Backup Strategy

### Automated Backups
- **RDS:** Daily automated backups, 7-day retention
- **EBS:** Daily snapshots via AWS Backup
- **S3:** Versioning + cross-region replication
- **DynamoDB:** Point-in-time recovery enabled

### Backup Verification
```bash
# Weekly restore test
aws backup start-restore-job \
  --recovery-point-arn <arn> \
  --metadata <test-config>
```

## Communication Plan

### DR Activation Notification
```markdown
**🚨 DISASTER RECOVERY ACTIVATED**

**Incident:** [Description]
**DR Region:** us-west-2
**Status:** In Progress
**ETA:** [Time]

**War Room:** [Zoom/Slack link]
**Status Updates:** Every 30 minutes

**Current Actions:**
- [ ] Database failover
- [ ] DNS update
- [ ] Application deployment
- [ ] Verification

**Next Update:** [Time]
```

## Post-DR Checklist

- [ ] All services operational in DR region
- [ ] Data integrity verified
- [ ] Monitoring restored
- [ ] Customers notified
- [ ] Incident postmortem scheduled
- [ ] DR procedures updated
- [ ] Failback plan documented
