# Alert to Runbook Mapping

## Critical Alerts (P0 - Immediate Response)

### Application Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| API-Complete-Outage | P0 | [Incident Response](/docs/runbooks/incident-response.md) | Check load balancer, pods, database |
| Database-Down | P0 | [Database Maintenance](/docs/runbooks/database-maintenance.md) | Check RDS status, failover to replica |
| All-Pods-Down | P0 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | `kubectl get pods -n <namespace>` |
| Load-Balancer-No-Healthy-Targets | P0 | [Incident Response](/docs/runbooks/incident-response.md) | Check target health, scale pods |

### Infrastructure Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| EKS-Cluster-Down | P0 | [Incident Response](/docs/runbooks/incident-response.md) | Contact AWS Support, activate DR |
| RDS-Primary-Down | P0 | [Disaster Recovery](/docs/runbooks/disaster-recovery.md) | Promote read replica |
| All-Nodes-NotReady | P0 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Check node status, ASG scaling |
| NAT-Gateway-Down | P0 | [Incident Response](/docs/runbooks/incident-response.md) | Create new NAT gateway |

### Security Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| GuardDuty-Critical-Finding | P0 | [Security Incidents](/docs/runbooks/security-incidents.md) | Review finding, isolate resources |
| Root-Account-Usage | P0 | [Security Incidents](/docs/runbooks/security-incidents.md) | Rotate credentials, review CloudTrail |
| Unauthorized-API-Calls-Spike | P0 | [Security Incidents](/docs/runbooks/security-incidents.md) | Block IPs, rotate keys |
| Data-Exfiltration-Detected | P0 | [Security Incidents](/docs/runbooks/security-incidents.md) | Block traffic, activate incident response |

## High Priority Alerts (P1 - 15 min response)

### Performance Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| API-Latency-High | P1 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Check database, scale pods |
| Error-Rate-Above-5% | P1 | [Incident Response](/docs/runbooks/incident-response.md) | Check logs, consider rollback |
| Database-CPU-High | P1 | [Database Maintenance](/docs/runbooks/database-maintenance.md) | Check slow queries, kill long-running |
| Pod-CPU-Throttling | P1 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Increase CPU limits, scale pods |

### Capacity Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| Database-Connections-High | P1 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Kill idle connections, increase max |
| Disk-Space-Low | P1 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Clean logs, increase volume size |
| Memory-Pressure | P1 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Scale pods, increase memory limits |
| EKS-Node-Pressure | P1 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Add nodes, enable cluster autoscaler |

### Deployment Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| Deployment-Failed | P1 | [Rollback Procedures](/docs/runbooks/rollback-procedures.md) | Review logs, rollback if needed |
| Pods-CrashLoopBackOff | P1 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Check logs, increase resources |
| ImagePullBackOff | P1 | [Deployment Procedures](/docs/runbooks/deployment-procedures.md) | Check image exists, verify credentials |

## Medium Priority Alerts (P2 - 1 hour response)

### Application Health

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| Health-Check-Failing | P2 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Check application logs |
| Error-Rate-Above-1% | P2 | [Incident Response](/docs/runbooks/incident-response.md) | Monitor, investigate if increasing |
| Latency-P99-High | P2 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Check database queries |
| Lambda-Throttling | P2 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Increase concurrency limits |

### Resource Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| CPU-Above-70% | P2 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Plan to scale |
| Memory-Above-80% | P2 | [Scaling Guide](/docs/runbooks/scaling-guide.md) | Plan to scale |
| Cache-Hit-Rate-Low | P2 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Review caching strategy |
| Database-Replica-Lag | P2 | [Database Maintenance](/docs/runbooks/database-maintenance.md) | Check replica performance |

### Security Monitoring

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| GuardDuty-Medium-Finding | P2 | [Security Incidents](/docs/runbooks/security-incidents.md) | Review and assess |
| Failed-Login-Spike | P2 | [Security Incidents](/docs/runbooks/security-incidents.md) | Review attempts, block if needed |
| Security-Group-Changed | P2 | [Security Incidents](/docs/runbooks/security-incidents.md) | Review change in CloudTrail |
| IAM-Policy-Changed | P2 | [Security Incidents](/docs/runbooks/security-incidents.md) | Review change, validate |

## Low Priority Alerts (P3 - 4 hour response)

### Operational Alerts

| Alert Name | Severity | Runbook | Quick Action |
|------------|----------|---------|--------------|
| Certificate-Expiring-30days | P3 | [Deployment Procedures](/docs/runbooks/deployment-procedures.md) | Renew certificate |
| Backup-Failed | P3 | [Database Maintenance](/docs/runbooks/database-maintenance.md) | Investigate, retry |
| Log-Errors-Detected | P3 | [Troubleshooting](/docs/runbooks/troubleshooting.md) | Review logs |
| Cost-Budget-Warning | P3 | Cost optimization review | Review spending |

## Alert Response Procedures

### Step 1: Acknowledge (< 5 minutes)
```bash
# In PagerDuty/Opsgenie
# Click "Acknowledge" button

# Or via CLI
curl -X PUT https://api.pagerduty.com/incidents/<id> \
  -H "Authorization: Token token=<api-key>" \
  -d '{"incident":{"type":"incident_reference","status":"acknowledged"}}'
```

### Step 2: Assess Severity
```markdown
Checklist:
- [ ] How many users affected?
- [ ] What is the customer impact?
- [ ] Are we in SLA breach?
- [ ] Is data at risk?
- [ ] Is there a security concern?
```

### Step 3: Follow Runbook
- Click the runbook link above
- Execute the "Quick Action" first
- Follow detailed procedures
- Document actions taken

### Step 4: Communicate
```markdown
## Alert Response Update

Alert: [Name]
Status: INVESTIGATING
Time: [HH:MM UTC]
Action: [What you're doing]
ETA: [Next update time]
```

### Step 5: Resolve or Escalate
```markdown
## Resolution
Alert: [Name]
Status: RESOLVED
Duration: [X minutes]
Root Cause: [Description]
Action Taken: [What fixed it]

OR

## Escalation
Alert: [Name]
Escalating to: [Person/Team]
Reason: [Why escalating]
Summary: [Current state]
```

## Alert Configuration

### CloudWatch Alarm Actions
All critical alarms should have:
- SNS topic subscription
- PagerDuty/Opsgenie integration
- Slack notification
- Auto-annotation in dashboards

### Alert Tuning
Review quarterly:
- False positive rate
- Time to acknowledge
- Time to resolve
- Alert fatigue indicators
- Runbook effectiveness

## Testing Alerts

### Monthly Alert Testing
```bash
# Test alert pipeline
# 1. Trigger test alarm
aws cloudwatch set-alarm-state \
  --alarm-name test-alert \
  --state-value ALARM \
  --state-reason "Testing alert pipeline"

# 2. Verify received in PagerDuty
# 3. Verify Slack notification
# 4. Verify SNS email
# 5. Reset alarm
aws cloudwatch set-alarm-state \
  --alarm-name test-alert \
  --state-value OK \
  --state-reason "Test complete"
```

## Alert Metrics

### Track These Metrics
- Mean Time to Acknowledge (MTTA)
- Mean Time to Resolve (MTTR)
- Alert volume per week
- False positive rate
- P0/P1 incidents per month
- SLA compliance

### Target Metrics
- MTTA: < 5 minutes
- MTTR: < 30 minutes
- False positive rate: < 5%
- P0 incidents: 0 per month
- SLA compliance: > 99.95%

## Alert Lifecycle

### New Alert Creation
1. Identify monitoring need
2. Define threshold and conditions
3. Create CloudWatch alarm
4. Configure SNS topic
5. Add to PagerDuty
6. Document runbook
7. Test alert
8. Train team

### Alert Modification
1. Review alert history
2. Analyze false positives
3. Adjust thresholds
4. Update runbook
5. Test changes
6. Document in changelog

### Alert Retirement
1. Review necessity
2. Check if superseded
3. Remove alarm
4. Update documentation
5. Archive runbook
6. Notify team

## Quick Reference

### Most Common Alerts

**Daily (Expected):**
- Cache evictions
- Scaling events
- Certificate renewals

**Weekly (Monitor):**
- Backup jobs
- Batch processing
- Maintenance windows

**Never (P0 if triggered):**
- Database down
- All pods down
- Security breach
- Data corruption

## Resources

- Alert Dashboard: https://console.aws.amazon.com/cloudwatch/alarms
- PagerDuty: https://company.pagerduty.com
- Slack: #incidents channel
- Runbooks: /docs/runbooks/
- Postmortems: /docs/postmortems/
