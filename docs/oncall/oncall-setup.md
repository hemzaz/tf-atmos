# On-Call Setup Guide

## Prerequisites

Before going on-call, ensure you have:

### Required Access
- [ ] AWS Console access (Production account)
- [ ] kubectl access to production EKS clusters
- [ ] PagerDuty/Opsgenie account with mobile app installed
- [ ] Slack access with notifications enabled
- [ ] VPN access (if required)
- [ ] GitHub repository access
- [ ] CloudWatch dashboard access
- [ ] Grafana access (if applicable)

### Tools Installation
```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Atmos
curl -sSL https://atmos.tools/install.sh | bash

# jq (JSON processor)
sudo apt-get install jq  # Debian/Ubuntu
brew install jq          # macOS
```

### AWS Authentication
```bash
# Configure AWS SSO
aws configure sso

# Login to production
aws sso login --profile production

# Configure kubectl
aws eks update-kubeconfig --name production-cluster --region us-east-1 --profile production

# Verify access
kubectl get nodes
kubectl get pods -A
```

### Testing Your Setup
```bash
# Test AWS access
aws sts get-caller-identity

# Test kubectl
kubectl cluster-info

# Test CloudWatch access
aws cloudwatch describe-alarms --state-value ALARM

# Test ability to scale
kubectl scale deployment/test-app -n test --replicas=1 --dry-run=client
```

## On-Call Schedule

### Rotation Details
- **Duration:** 1 week (Monday 9:00 AM - Monday 9:00 AM)
- **Primary:** Handles all incidents
- **Secondary:** Backup for primary, escalation point
- **Handoff:** Monday morning standup

### Handoff Process

**Outgoing Engineer:**
1. Send handoff summary in `#oncall-handoff` channel
2. Review open incidents
3. Highlight any ongoing issues
4. Share lessons learned
5. Update runbooks if needed

**Incoming Engineer:**
1. Review handoff notes
2. Check current system status
3. Verify access to all tools
4. Test alert receiving
5. Acknowledge handoff

### Handoff Template
```markdown
## On-Call Handoff - Week of [Date]

**Outgoing:** [Name]
**Incoming:** [Name]

### Week Summary
- Total incidents: X
- P0: X | P1: X | P2: X | P3: X
- Most common issue: [Description]

### Open Items
- [ ] [Issue 1 - Status]
- [ ] [Issue 2 - Status]

### Ongoing Concerns
- [System/Component]: [Description and monitoring]

### Key Metrics
- Uptime: XX.XX%
- MTTR: XX minutes
- Error rate: X.XX%

### Upcoming Changes
- [Deployment/Maintenance planned]

### Notes
[Any additional context]
```

## Alert Response

### Initial Response (First 5 Minutes)
1. **Acknowledge alert** in PagerDuty/Opsgenie
2. **Assess severity** using runbooks
3. **Join incident channel** `#incident-response`
4. **Check dashboards** for current state
5. **Begin investigation** or escalate

### Communication
```markdown
## Initial Response Template

Alert: [Alert Name]
Time: [HH:MM UTC]
Status: INVESTIGATING
Initial Assessment: [Brief description]

Actions:
- Checking [system/service]
- Reviewing recent changes
- ETA for update: 15 minutes
```

## Tools and Resources

### Dashboards
- Production Infrastructure: https://console.aws.amazon.com/cloudwatch/dashboards
- Application Metrics: https://grafana.company.com/d/production
- Security Events: https://console.aws.amazon.com/securityhub

### Runbooks
- [Incident Response](/docs/runbooks/incident-response.md)
- [Deployment Procedures](/docs/runbooks/deployment-procedures.md)
- [Rollback Procedures](/docs/runbooks/rollback-procedures.md)
- [Scaling Guide](/docs/runbooks/scaling-guide.md)
- [Troubleshooting](/docs/runbooks/troubleshooting.md)
- [Disaster Recovery](/docs/runbooks/disaster-recovery.md)
- [Security Incidents](/docs/runbooks/security-incidents.md)
- [Database Maintenance](/docs/runbooks/database-maintenance.md)

### Quick Commands Cheat Sheet
```bash
# AWS
aws sso login --profile production
aws sts get-caller-identity

# Kubernetes
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod> --tail=100
kubectl describe pod -n <namespace> <pod>
kubectl scale deployment/<name> -n <namespace> --replicas=<count>

# Monitoring
aws cloudwatch describe-alarms --state-value ALARM
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'

# Terraform
cd stacks/deployments/<path>
atmos terraform plan <component> -s <stack>
```

## Escalation

### When to Escalate
- Unable to resolve P0/P1 within 30 minutes
- Need additional expertise
- Major infrastructure decision required
- Security incident detected
- Customer data at risk

### Escalation Path
1. **Level 1:** Secondary on-call engineer
2. **Level 2:** Team Lead
3. **Level 3:** Engineering Manager
4. **Level 4:** VP Engineering / CTO

### Escalation Template
```markdown
## Escalation Request

**From:** [Your Name]
**To:** [Escalation Contact]
**Severity:** [P0/P1/P2]
**Duration:** [How long incident has been ongoing]

**Issue:** [Brief description]

**Attempted Actions:**
- [Action 1]
- [Action 2]

**Current Status:** [System state]

**Need:** [Specific help needed]
```

## Best Practices

### Do's
- Acknowledge alerts promptly
- Communicate early and often
- Document actions taken
- Ask for help when needed
- Follow runbooks
- Keep calm under pressure
- Learn from incidents

### Don'ts
- Make changes without understanding impact
- Skip communication
- Ignore minor alerts (they can escalate)
- Forget to document
- Work beyond your knowledge limits
- Delay escalation when needed

## Self-Care

### Managing On-Call Stress
- Set boundaries for non-critical alerts
- Take breaks during quiet periods
- Exercise and maintain routine
- Get adequate sleep when possible
- Use secondary/backup when needed
- Debrief after major incidents

### Sleep Hygiene
- Keep phone volume appropriate (audible but not jarring)
- Use smart watch for subtle alerts
- Have laptop nearby and charged
- Inform household about on-call
- Prepare caffeine for emergencies

### After Hours
- Keep response time to < 15 minutes
- Have stable internet connection
- Be in location with good cell signal
- Inform team if traveling
- Test remote access before on-call week

## Compensation

- On-call pay: [Rate/details per company policy]
- Incident response: [Overtime policy]
- Weekend coverage: [Additional compensation]

## Support

### Resources
- On-call Slack channel: `#oncall-support`
- Team lead: [Name, Phone, Email]
- Engineering manager: [Name, Phone, Email]
- Secondary on-call: Check PagerDuty

### Questions?
Ask in `#oncall-support` or reach out to your team lead.

## Checklist

### Before On-Call Week
- [ ] All tools installed and tested
- [ ] AWS access verified
- [ ] kubectl configured
- [ ] PagerDuty/Opsgenie app installed
- [ ] Mobile notifications enabled
- [ ] VPN tested (if applicable)
- [ ] Runbooks reviewed
- [ ] Dashboard bookmarks saved
- [ ] Emergency contacts saved
- [ ] Laptop charged and ready

### During On-Call Week
- [ ] Check system status daily
- [ ] Review monitoring dashboards
- [ ] Stay within 15-min response range
- [ ] Keep tools accessible
- [ ] Document all incidents
- [ ] Communicate with team

### After On-Call Week
- [ ] Complete handoff
- [ ] File postmortems
- [ ] Update runbooks
- [ ] Share learnings
- [ ] Take a break
