# SRE Implementation Deployment Checklist

## Pre-Deployment

### Prerequisites
- [ ] AWS credentials configured with admin access
- [ ] Terraform/Atmos CLI installed and configured
- [ ] kubectl access to production clusters verified
- [ ] Team briefed on new monitoring and procedures
- [ ] PagerDuty/Opsgenie accounts created for team
- [ ] Slack channels created (#incidents, #oncall-support)

### Review
- [ ] All runbooks reviewed by team
- [ ] On-call rotation schedule created
- [ ] Escalation contacts confirmed
- [ ] SLA/SLO targets approved by stakeholders
- [ ] Alert thresholds validated against current metrics

## Phase 1: Security Monitoring (Week 1)

### Deploy Security Monitoring Component
```bash
cd /Users/elad/PROJ/tf-atmos
atmos terraform plan security-monitoring -s <stack>
atmos terraform apply security-monitoring -s <stack>
```

- [ ] GuardDuty detector enabled
- [ ] Security Hub activated with standards (CIS, FSBP)
- [ ] Inspector V2 scanning enabled (EC2, ECR, Lambda)
- [ ] SNS topic created for security alerts
- [ ] Email subscriptions confirmed
- [ ] EventBridge rules configured
- [ ] Test alert sent and received

### Configure Security Alert Recipients
- [ ] Security team email added to subscriptions
- [ ] Slack webhook configured (if using Lambda enrichment)
- [ ] PagerDuty integration tested

### Verification
- [ ] GuardDuty findings visible in console
- [ ] Security Hub standards running
- [ ] Inspector scans completing
- [ ] Alert received when test finding created
- [ ] CloudWatch alarms showing in dashboard

## Phase 2: Enhanced Monitoring (Week 1-2)

### Update Monitoring Configuration
```bash
# Update stack configuration with monitoring variables
atmos terraform plan monitoring -s <stack>
atmos terraform apply monitoring -s <stack>
```

- [ ] Comprehensive alarms deployed
- [ ] Infrastructure dashboard created
- [ ] Security dashboard created
- [ ] Application dashboard created
- [ ] SNS topics configured
- [ ] Email subscriptions active

### Configure Monitoring
- [ ] RDS instance IDs added to variables
- [ ] Lambda function names configured
- [ ] EKS cluster name set
- [ ] Load balancer ARNs provided
- [ ] Alert thresholds adjusted for environment

### Verification
- [ ] All alarms in OK state (or justified ALARM state)
- [ ] Dashboards displaying metrics
- [ ] Test alarm triggers successfully
- [ ] Notifications received (email, Slack, PagerDuty)
- [ ] No false positives in first 24 hours

## Phase 3: Backup Automation (Week 2)

### Deploy Backup Component
```bash
atmos terraform plan backup -s <stack>
atmos terraform apply backup -s <stack>
```

- [ ] Primary backup vault created
- [ ] Cross-region vault created (if enabled)
- [ ] KMS encryption configured
- [ ] Daily backup plan active
- [ ] Weekly backup plan active
- [ ] Monthly backup plan active
- [ ] Backup selections configured
- [ ] SNS notifications setup

### Configure Backup Resources
- [ ] RDS instances added to backup
- [ ] DynamoDB tables included
- [ ] EFS file systems configured
- [ ] EC2 instances tagged (Backup=true)
- [ ] EBS volumes identified

### Test Backup Process
- [ ] Wait 24 hours for first backup
- [ ] Verify backup job completed successfully
- [ ] Check recovery points in vault
- [ ] Perform test restore to isolated environment
- [ ] Validate restored data
- [ ] Document restore time (RTO measurement)

### Verification
- [ ] Backup jobs running on schedule
- [ ] Recovery points accumulating
- [ ] Cross-region copies successful (if enabled)
- [ ] Notifications received for backup events
- [ ] Backup compliance report generated

## Phase 4: Team Onboarding (Week 2-3)

### Documentation Review
- [ ] All team members read runbooks
- [ ] Incident response procedure walkthrough
- [ ] Deployment procedures reviewed
- [ ] Rollback procedures practiced (tabletop)
- [ ] Escalation policy understood

### Access Setup
- [ ] PagerDuty accounts created for all engineers
- [ ] Mobile apps installed and tested
- [ ] AWS console access verified
- [ ] kubectl access confirmed
- [ ] VPN access tested (if required)
- [ ] Slack channels joined
- [ ] On-call schedule published

### Training Sessions
- [ ] Incident response training (2 hours)
- [ ] Runbook walkthrough (1 hour)
- [ ] Dashboard and monitoring training (1 hour)
- [ ] Security incident procedures (1 hour)
- [ ] Q&A session completed

### Tabletop Exercises
- [ ] P0 incident simulation
- [ ] Database failure scenario
- [ ] Security incident response
- [ ] Escalation practice
- [ ] Rollback procedure rehearsal

## Phase 5: On-Call Activation (Week 3)

### Setup On-Call Rotation
- [ ] Primary and secondary roles assigned
- [ ] First rotation schedule published (4 weeks out)
- [ ] Handoff process documented
- [ ] Handoff template shared
- [ ] Compensation confirmed

### Alert Configuration
- [ ] PagerDuty escalation policy configured
- [ ] Alert routing rules set
- [ ] Quiet hours configured (if applicable)
- [ ] Alert suppression rules (maintenance windows)
- [ ] Test page sent to first on-call engineer

### First Week Monitoring
- [ ] Shadow on-call for first week (optional)
- [ ] Daily standup discussions about alerts
- [ ] Runbook improvements identified
- [ ] False positive tuning
- [ ] Alert fatigue assessment

### Verification
- [ ] First on-call week completed
- [ ] Handoff process successful
- [ ] No missed alerts
- [ ] Response times within SLA
- [ ] Feedback collected and documented

## Phase 6: Production Validation (Week 4)

### End-to-End Testing
- [ ] Trigger P2 test incident
- [ ] Follow incident response runbook
- [ ] Verify communication flow
- [ ] Test escalation (notify but don't page)
- [ ] Document time to resolution
- [ ] Create test postmortem

### Disaster Recovery Drill
- [ ] Schedule DR drill (communicate widely)
- [ ] Simulate region failure
- [ ] Follow DR runbook
- [ ] Measure RTO/RPO
- [ ] Document lessons learned
- [ ] Update DR procedures

### Security Incident Drill
- [ ] Simulate security finding (GuardDuty test event)
- [ ] Follow security incident runbook
- [ ] Test isolation procedures
- [ ] Verify forensic data collection
- [ ] Document response timeline
- [ ] Update security procedures

### Performance Validation
- [ ] All alarms tuned (< 5% false positive rate)
- [ ] Dashboards showing accurate data
- [ ] Backup restore tested successfully
- [ ] MTTA < 5 minutes achieved
- [ ] MTTR < 30 minutes achieved
- [ ] SLO compliance > 99.95%

## Ongoing Operations

### Daily
- [ ] Check CloudWatch alarm status
- [ ] Review security findings
- [ ] Monitor error budget
- [ ] Verify backup job completion

### Weekly
- [ ] On-call handoff meeting
- [ ] Incident metrics review
- [ ] SLO compliance check
- [ ] Runbook updates (if needed)

### Monthly
- [ ] Backup restoration test
- [ ] Alert tuning review
- [ ] Tabletop exercise
- [ ] SLO review meeting
- [ ] Cost optimization review

### Quarterly
- [ ] Full DR drill
- [ ] Security posture review
- [ ] Escalation contact update
- [ ] SLA compliance review
- [ ] Capacity planning assessment

## Success Metrics

### Week 1 Targets
- [ ] Security monitoring deployed
- [ ] GuardDuty findings reviewed
- [ ] Zero P0 security incidents missed

### Week 2 Targets
- [ ] All alarms deployed
- [ ] Dashboards operational
- [ ] Backup jobs running
- [ ] Team trained on basics

### Week 4 Targets
- [ ] On-call rotation active
- [ ] MTTA < 5 minutes
- [ ] MTTR < 30 minutes
- [ ] Zero missed pages
- [ ] > 95% team confidence

### 90-Day Targets
- [ ] SLO compliance > 99.95%
- [ ] Error budget > 50%
- [ ] Zero P0 incidents
- [ ] All runbooks validated
- [ ] Team feedback positive

## Rollback Plan

If major issues encountered:

### Phase 1-2 Rollback
```bash
# Disable alarms
aws cloudwatch disable-alarm-actions --alarm-names <alarm-name>

# Remove SNS subscriptions
aws sns unsubscribe --subscription-arn <arn>

# Destroy components (if needed)
atmos terraform destroy security-monitoring -s <stack>
atmos terraform destroy monitoring -s <stack>
```

### Phase 3 Rollback
```bash
# Disable backup plans (don't destroy - keep existing backups!)
aws backup update-backup-plan --backup-plan-id <id> --backup-plan <disabled-plan>
```

### Phase 4-5 Rollback
- Revert to previous on-call system
- Continue using old runbooks
- Disable PagerDuty routing

## Support

### Issues During Deployment
- **Contact:** SRE Team Lead
- **Slack:** #sre-implementation
- **Documentation:** /docs/SRE_IMPLEMENTATION_SUMMARY.md

### Post-Deployment Support
- **On-Call:** #oncall-support
- **Runbooks:** /docs/runbooks/
- **Escalation:** /docs/oncall/escalation-policy.md

## Sign-Off

### Deployment Approval
- [ ] Engineering Manager approval
- [ ] Security team review
- [ ] Operations team ready
- [ ] Budget approved
- [ ] Change management ticket created

### Post-Deployment Sign-Off
- [ ] All phases completed
- [ ] All tests passed
- [ ] Team trained
- [ ] Documentation complete
- [ ] Metrics baseline established

**Deployment Lead:** _______________  **Date:** _______________

**Engineering Manager:** _______________  **Date:** _______________

**Operations Lead:** _______________  **Date:** _______________

---

**For questions or issues, refer to:**
- Summary: `/Users/elad/PROJ/tf-atmos/docs/SRE_IMPLEMENTATION_SUMMARY.md`
- Runbooks: `/Users/elad/PROJ/tf-atmos/docs/runbooks/`
- On-Call: `/Users/elad/PROJ/tf-atmos/docs/oncall/`
