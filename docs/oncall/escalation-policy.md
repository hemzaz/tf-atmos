# Escalation Policy

## Overview

This document defines the escalation procedures for production incidents based on severity and response requirements.

## Escalation Levels

### Level 1: On-Call Engineer
- **Role:** Primary incident responder
- **Responsibility:** Acknowledge, investigate, and resolve incidents
- **Response Time:**
  - P0: Immediate (< 5 minutes)
  - P1: < 15 minutes
  - P2: < 1 hour
  - P3: < 4 hours

### Level 2: Secondary On-Call
- **Role:** Backup and additional expertise
- **When to Escalate:**
  - Primary unresponsive after 10 minutes
  - Need additional technical expertise
  - P0/P1 incident ongoing > 30 minutes
- **Response Time:** < 15 minutes

### Level 3: Team Lead
- **Role:** Technical oversight and decision-making
- **When to Escalate:**
  - P0 incident ongoing > 30 minutes
  - P1 incident ongoing > 2 hours
  - Major infrastructure decision needed
  - Customer escalation
- **Response Time:** < 30 minutes

### Level 4: Engineering Manager
- **Role:** Resource allocation and stakeholder management
- **When to Escalate:**
  - P0 incident ongoing > 1 hour
  - Multiple simultaneous P1 incidents
  - Need additional team resources
  - Executive stakeholder involvement needed
- **Response Time:** < 1 hour

### Level 5: VP Engineering / CTO
- **Role:** Executive decision-making and external communication
- **When to Escalate:**
  - P0 incident ongoing > 2 hours
  - Major business impact
  - Potential data breach
  - Media attention likely
  - Legal/regulatory implications
- **Response Time:** < 2 hours

## Escalation Triggers

### Automatic Escalation

| Severity | Duration | Escalate To |
|----------|----------|-------------|
| P0 | 30 min | Team Lead |
| P0 | 1 hour | Engineering Manager |
| P0 | 2 hours | VP Engineering |
| P1 | 2 hours | Team Lead |
| P1 | 4 hours | Engineering Manager |
| P2 | 8 hours | Team Lead |

### Immediate Escalation Scenarios

**Escalate to Team Lead immediately:**
- Data breach suspected
- Security vulnerability being exploited
- Complete service outage
- Database corruption detected
- Multiple regions affected

**Escalate to Engineering Manager immediately:**
- Active data breach confirmed
- Critical security vulnerability
- Potential legal/regulatory violation
- Multiple services down
- Customer SLA breach

**Escalate to VP/CTO immediately:**
- Confirmed data breach with customer data exposure
- Regulatory reporting required (GDPR, HIPAA, etc.)
- Media attention or social media escalation
- Major customer threatening contract termination
- Law enforcement involvement

## Escalation Process

### Step 1: Assess Need for Escalation
```markdown
## Escalation Decision Checklist

- [ ] Have I exhausted my technical knowledge?
- [ ] Is the incident severity beyond my authority?
- [ ] Has the incident exceeded time thresholds?
- [ ] Do I need additional resources?
- [ ] Is there customer/business impact requiring management involvement?
- [ ] Are there security/legal implications?
```

### Step 2: Prepare Escalation Summary
```markdown
## Escalation Summary Template

**Time:** [HH:MM UTC]
**Severity:** [P0/P1/P2/P3]
**Duration:** [How long incident has been active]
**Services Affected:** [List]

**Impact:**
- Users affected: [Number/percentage]
- Business impact: [Description]
- Revenue impact: [If known]

**Timeline:**
- [HH:MM] - [Event]
- [HH:MM] - [Action taken]
- [HH:MM] - [Current state]

**Actions Taken:**
1. [Action 1 - Result]
2. [Action 2 - Result]
3. [Action 3 - Result]

**Current Hypothesis:**
[Your understanding of root cause]

**Reason for Escalation:**
[Specific help/decision needed]

**Next Steps:**
[What you plan to try next or need approval for]
```

### Step 3: Initiate Escalation

**Via PagerDuty/Opsgenie:**
```bash
# Escalate incident
# In PagerDuty UI: Click "Escalate" button
# OR via CLI:
curl -X POST https://api.pagerduty.com/incidents/<incident-id>/escalate \
  -H "Authorization: Token token=<api-key>" \
  -H "Content-Type: application/json" \
  -d '{"escalation_level": 2}'
```

**Via Phone:**
- Primary: Call escalation contact directly
- Backup: Send SMS if no answer in 2 minutes
- Always: Post in Slack incident channel

**Via Slack:**
```markdown
@[escalation-contact] - Escalating P0 incident

Current status: [Brief description]
Need: [Specific help required]
Summary: [Link to incident doc]
```

### Step 4: Brief Escalation Contact

When contact is established:
1. State severity and duration
2. Summarize current state
3. Explain actions taken
4. Share hypothesis
5. State specific need (decision, expertise, resources)
6. Answer questions
7. Agree on next steps

### Step 5: Continue Incident Response

- Remain incident commander unless handoff occurs
- Execute agreed-upon actions
- Keep escalation contact informed
- Provide updates every 15-30 minutes
- Document all decisions and actions

## De-escalation

### When to De-escalate
- Incident resolved or significantly mitigated
- Severity downgraded (e.g., P0 → P1)
- Additional resources no longer needed
- Situation stable and under control

### De-escalation Notification
```markdown
## De-escalation Notice

**Incident:** [Brief description]
**Previous Severity:** P0
**Current Severity:** P1
**Status:** Resolved / Mitigated

**Resolution:**
[What fixed the issue]

**Next Steps:**
- Monitoring for recurrence
- Root cause analysis scheduled
- Postmortem: [Date/Time]

Thank you for your support.
```

## Special Escalation Paths

### Security Incidents
```
On-Call Engineer
    ↓
Security Team (immediate)
    ↓
CISO + Engineering Manager (within 30 min)
    ↓
Legal + PR (if data breach)
```

### Database Issues
```
On-Call Engineer
    ↓
DBA / Database Specialist (immediate)
    ↓
Team Lead (if ongoing > 30 min)
```

### External Service Outages
```
On-Call Engineer
    ↓
Vendor Support (immediate)
    ↓
Team Lead (status updates)
    ↓
Engineering Manager (if SLA breach)
```

## Escalation Contacts

### Engineering Team

| Role | Name | Phone | Email | Slack |
|------|------|-------|-------|-------|
| Primary On-Call | [See PagerDuty] | - | - | - |
| Secondary On-Call | [See PagerDuty] | - | - | - |
| Team Lead | [Name] | [Phone] | [Email] | @handle |
| Engineering Manager | [Name] | [Phone] | [Email] | @handle |
| VP Engineering | [Name] | [Phone] | [Email] | @handle |
| CTO | [Name] | [Phone] | [Email] | @handle |

### Specialized Teams

| Team | Contact | When to Engage |
|------|---------|----------------|
| Security | [Email/Slack] | Security incidents |
| Database | [Email/Slack] | Database issues |
| Infrastructure | [Email/Slack] | AWS/networking |
| DevOps | [Email/Slack] | CI/CD, deployments |
| Customer Success | [Email/Slack] | Customer escalations |

### External Contacts

| Vendor | Support Phone | Support Email | Account # |
|--------|--------------|---------------|-----------|
| AWS | Premium Support | - | [Account ID] |
| [Database Vendor] | [Phone] | [Email] | [Account] |
| [CDN Provider] | [Phone] | [Email] | [Account] |

## Communication During Escalation

### Incident Channel Updates
```markdown
## Escalation Update

@here - Escalating to [Level/Person]

**Status:** [Current state]
**Escalation Reason:** [Why escalating]
**ETA for Next Update:** [Time]

[Incident Commander] remains IC unless notified otherwise.
```

### Stakeholder Communication

**For P0 incidents, notify:**
- Engineering leadership (immediate)
- Customer Success (within 15 min)
- Product Management (within 30 min)
- Executive team (within 1 hour if ongoing)

**Communication channels:**
- Internal: Slack `#incidents`
- External: Status page updates
- Customers: Via Customer Success team

## Post-Escalation

### Escalation Metrics
Track for continuous improvement:
- Time to escalate
- Escalation reason
- Was escalation necessary?
- What could prevent future escalation?
- Resolution time after escalation

### Escalation Review

During postmortem, assess:
- Was escalation timely?
- Was the right person/team engaged?
- Did escalation help resolve faster?
- What would improve the process?
- Are runbooks adequate?

## Training

### For On-Call Engineers
- Review escalation triggers monthly
- Practice escalation scenarios quarterly
- Know your escalation contacts
- Understand when to escalate vs. resolve
- Don't hesitate to escalate when needed

### For Escalation Contacts
- Keep contact info current
- Test escalation path quarterly
- Provide feedback to on-call team
- Be available during designated times
- Participate in postmortems

## References

- [On-Call Setup](/docs/oncall/oncall-setup.md)
- [Incident Response](/docs/runbooks/incident-response.md)
- [SLA/SLO Targets](/docs/oncall/sla-slo-targets.md)
