# Incident Response Runbook

## Overview

This runbook provides step-by-step procedures for responding to production incidents, categorized by severity level.

## Severity Levels

| Severity | Description | Response Time | Escalation |
|----------|-------------|---------------|------------|
| **P0** | Complete outage, customer-facing | Immediate | Escalate to leadership immediately |
| **P1** | Major degradation, multiple customers affected | < 15 minutes | Escalate after 30 minutes |
| **P2** | Partial degradation, limited customer impact | < 1 hour | Escalate after 2 hours |
| **P3** | Minor issue, minimal customer impact | < 4 hours | Escalate after 8 hours |

## Incident Response Process

### 1. Detection and Triage (0-5 minutes)

**When Alert Fires:**

```bash
# Step 1: Acknowledge the alert in PagerDuty/Opsgenie
# Step 2: Join the incident response channel
# Step 3: Check monitoring dashboards

# Access dashboards
https://console.aws.amazon.com/cloudwatch/dashboards

# Check application health
aws cloudwatch get-dashboard --dashboard-name <environment>-infrastructure-overview

# Check recent deployments
kubectl rollout history deployment -n <namespace>
```

**Initial Assessment:**
- What service is impacted?
- What is the customer impact?
- When did the issue start?
- Are there any recent changes?

### 2. Communication (First 10 minutes)

**Incident Commander Actions:**

```markdown
## Incident Communication Template

**Severity:** P0/P1/P2/P3
**Status:** INVESTIGATING
**Impact:** [Describe customer impact]
**Started At:** [Timestamp]
**Services Affected:** [List services]
**Current Action:** [What team is doing]

Next update in: 30 minutes
```

**Communication Channels:**
- Internal: `#incident-response` Slack channel
- External: Status page updates
- Leadership: Direct notification for P0/P1

### 3. Investigation (Concurrent with mitigation)

**Gather Information:**

```bash
# Check application logs
kubectl logs -n <namespace> <pod-name> --tail=500 --timestamps

# Check CloudWatch Logs Insights
# Query recent errors:
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# Check recent deployments
aws deploy list-deployments --application-name <app-name> --max-items 10

# Check infrastructure changes
git log --since="4 hours ago" --oneline

# Check CloudTrail for AWS changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventTime,AttributeValue=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --max-items 50
```

**Common Investigation Points:**
1. Recent deployments (last 4 hours)
2. Infrastructure changes (CloudFormation, Terraform)
3. Configuration changes (ConfigMaps, environment variables)
4. External dependencies (third-party APIs, databases)
5. Resource exhaustion (CPU, memory, disk, connections)
6. Security events (GuardDuty, Security Hub findings)

### 4. Mitigation (Priority: Restore service)

**Quick Mitigation Options:**

#### Application Issues

```bash
# Rollback deployment
kubectl rollout undo deployment/<deployment-name> -n <namespace>

# Scale up replicas
kubectl scale deployment/<deployment-name> --replicas=<count> -n <namespace>

# Restart pods
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Check pod status
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>
```

#### Database Issues

```bash
# Check RDS connections
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].DBInstanceStatus'

# Check RDS CPU/Memory
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average

# Kill long-running queries (PostgreSQL)
# Connect to RDS and run:
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active' AND query_start < NOW() - INTERVAL '5 minutes';
```

#### Infrastructure Issues

```bash
# Check EC2 instance health
aws ec2 describe-instance-status --instance-ids <instance-id>

# Reboot instance
aws ec2 reboot-instances --instance-ids <instance-id>

# Check EKS node status
kubectl get nodes
kubectl describe node <node-name>

# Drain and replace node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Wait for ASG to replace node
```

#### Load Balancer Issues

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Check ALB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=<lb-name> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average,Maximum
```

### 5. Resolution Verification

**Verification Checklist:**

```bash
# 1. Check application health endpoints
curl -I https://<domain>/health

# 2. Verify monitoring metrics are green
# Check CloudWatch dashboard

# 3. Test critical user flows
# Execute synthetic tests

# 4. Verify no error spikes
# Query logs for errors

# 5. Check resource utilization
kubectl top pods -n <namespace>
kubectl top nodes
```

### 6. Post-Incident (Within 48 hours)

**Immediate Actions:**
1. Update incident status to RESOLVED
2. Send resolution communication
3. Thank the team
4. Schedule postmortem meeting

**Postmortem Template:**

```markdown
# Postmortem: [Incident Title]

**Date:** YYYY-MM-DD
**Duration:** X hours Y minutes
**Severity:** PX
**Incident Commander:** [Name]

## Impact
- Customer impact: [Description]
- Revenue impact: $[Amount]
- Affected services: [List]
- Number of affected users: [Count]

## Timeline
- HH:MM - [Event]
- HH:MM - [Event]
- HH:MM - [Resolution]

## Root Cause
[Detailed explanation of what caused the incident]

## Resolution
[What fixed the issue]

## What Went Well
- [Item 1]
- [Item 2]

## What Could Be Improved
- [Item 1]
- [Item 2]

## Action Items
| Action | Owner | Deadline | Status |
|--------|-------|----------|--------|
| [Task] | [Name] | YYYY-MM-DD | Open |

## Lessons Learned
[Key takeaways]
```

## Severity-Specific Procedures

### P0: Complete Outage

**Immediate Actions (First 5 minutes):**
1. Page on-call engineer + backup
2. Notify leadership (CTO, VP Engineering)
3. Create war room (Zoom/Slack huddle)
4. Update external status page
5. Activate incident commander role

**Communication Frequency:**
- Updates every 15 minutes
- Status page updates every 30 minutes

**Escalation Path:**
1. On-call engineer (0 minutes)
2. Team lead (5 minutes)
3. Engineering manager (15 minutes)
4. VP Engineering (30 minutes)
5. CTO (45 minutes)

### P1: Major Degradation

**Immediate Actions (First 15 minutes):**
1. Page on-call engineer
2. Notify team lead
3. Join incident response channel
4. Begin investigation

**Communication Frequency:**
- Updates every 30 minutes
- Status page updates every hour

**Escalation Path:**
1. On-call engineer (0 minutes)
2. Team lead (30 minutes)
3. Engineering manager (2 hours)

### P2: Partial Degradation

**Immediate Actions (First hour):**
1. Notify on-call engineer
2. Begin investigation
3. Document findings

**Communication Frequency:**
- Updates every 2 hours

**Escalation Path:**
1. On-call engineer (0 minutes)
2. Team lead (2 hours)

### P3: Minor Issue

**Immediate Actions (First 4 hours):**
1. Create ticket
2. Investigate when available
3. Document findings

**Communication Frequency:**
- Daily updates

## Common Scenarios

### Scenario 1: API Latency Spike

```bash
# 1. Check load balancer metrics
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB ...

# 2. Check database performance
# Review slow query logs

# 3. Check for recent deployments
kubectl rollout history deployment -n <namespace>

# 4. Scale up if needed
kubectl scale deployment/<name> --replicas=<new-count> -n <namespace>

# 5. Enable connection pooling if not already enabled
# 6. Consider read replica for read-heavy workloads
```

### Scenario 2: Database Connection Exhaustion

```bash
# 1. Check current connections
aws rds describe-db-instances --db-instance-identifier <id> \
  | jq '.DBInstances[0].DBParameterGroups'

# 2. Kill idle connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND state_change < NOW() - INTERVAL '10 minutes';

# 3. Increase max_connections parameter
aws rds modify-db-parameter-group \
  --db-parameter-group-name <name> \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=immediate"

# 4. Reboot RDS instance (if required)
aws rds reboot-db-instance --db-instance-identifier <id>
```

### Scenario 3: Pod CrashLoopBackOff

```bash
# 1. Get pod status
kubectl get pods -n <namespace>

# 2. Describe pod
kubectl describe pod <pod-name> -n <namespace>

# 3. Check logs
kubectl logs <pod-name> -n <namespace> --previous

# 4. Check resource limits
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 resources

# 5. Increase resources if OOMKilled
kubectl set resources deployment/<name> -n <namespace> \
  --limits=memory=1Gi --requests=memory=512Mi
```

## Tools and Access

**Required Access:**
- AWS Console (Production account)
- kubectl access to EKS clusters
- PagerDuty/Opsgenie access
- Slack incident channels
- Grafana/CloudWatch dashboards
- Log aggregation (CloudWatch Logs Insights)

**Useful Commands:**

```bash
# Authenticate to AWS
aws sso login --profile production

# Get kubectl context
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Set context
kubectl config use-context <context-name>

# Quick cluster overview
kubectl get all -A
```

## Contact Information

**On-Call Rotation:**
- Primary: Check PagerDuty schedule
- Secondary: Check PagerDuty schedule

**Escalation Contacts:**
- Team Lead: [Name] - [Phone] - [Email]
- Engineering Manager: [Name] - [Phone] - [Email]
- VP Engineering: [Name] - [Phone] - [Email]
- CTO: [Name] - [Phone] - [Email]

**External Vendors:**
- AWS Support: Premium Support phone number
- Database Vendor: Support contact
- CDN Provider: Support contact

## References

- [Deployment Procedures](/docs/runbooks/deployment-procedures.md)
- [Rollback Procedures](/docs/runbooks/rollback-procedures.md)
- [Scaling Guide](/docs/runbooks/scaling-guide.md)
- [Disaster Recovery](/docs/runbooks/disaster-recovery.md)
