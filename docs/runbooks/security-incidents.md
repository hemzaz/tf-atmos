# Security Incident Response

## Severity Classification

| Level | Description | Response Time |
|-------|-------------|---------------|
| **Critical** | Active breach, data exfiltration | Immediate |
| **High** | Vulnerability with exploit available | < 4 hours |
| **Medium** | Vulnerability without known exploit | < 24 hours |
| **Low** | Minor security issue | < 1 week |

## Incident Types

### 1. Unauthorized Access Detected

**Indicators:**
- GuardDuty findings: UnauthorizedAccess
- Failed authentication spike
- Unusual API calls
- Access from suspicious IPs

**Immediate Actions:**
```bash
# 1. Rotate affected credentials
aws iam update-access-key --access-key-id <key-id> --status Inactive --user-name <user>

# 2. Review CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=<user> \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --max-items 100

# 3. Block suspicious IP
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --ip-permissions IpProtocol=-1,FromPort=-1,ToPort=-1,IpRanges='[{CidrIp=<malicious-ip>/32,Description=Blocked}]' \
  --rule-action deny

# 4. Enable MFA for affected users
aws iam enable-mfa-device --user-name <user> --serial-number <mfa-arn> --authentication-code1 <code1> --authentication-code2 <code2>
```

### 2. Data Breach Suspected

**Indicators:**
- Large data egress detected
- S3 bucket policy changes
- Database export activities
- GuardDuty Exfiltration findings

**Immediate Actions:**
```bash
# 1. Block outbound traffic to suspicious destinations
aws ec2 authorize-security-group-egress \
  --group-id <sg-id> \
  --ip-permissions ... \
  --rule-action deny

# 2. Review S3 access logs
aws s3api get-bucket-logging --bucket <bucket-name>
aws s3 cp s3://<log-bucket>/<prefix>/ . --recursive

# 3. Enable S3 MFA delete
aws s3api put-bucket-versioning \
  --bucket <bucket-name> \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "<mfa-serial> <token-code>"

# 4. Notify legal/compliance team
# 5. Begin forensic analysis
```

### 3. Malware/Crypto-mining Detected

**Indicators:**
- Unusual CPU usage patterns
- Network connections to known bad IPs
- GuardDuty CryptoCurrency findings
- Inspector malware findings

**Immediate Actions:**
```bash
# 1. Isolate affected instances
aws ec2 modify-instance-attribute \
  --instance-id <instance-id> \
  --groups <isolated-sg-id>

# 2. Take snapshot for forensics
aws ec2 create-snapshot \
  --volume-id <volume-id> \
  --description "Forensic snapshot $(date +%Y%m%d-%H%M%S)"

# 3. Terminate affected instances
aws ec2 terminate-instances --instance-ids <instance-id>

# 4. Scan other instances
# Deploy malware scanner
```

### 4. DDoS Attack

**Indicators:**
- Sudden traffic spike
- High load balancer request count
- CloudWatch alarms firing
- Service degradation

**Immediate Actions:**
```bash
# 1. Enable AWS Shield Advanced (if available)
# 2. Enable WAF rate limiting

# 3. Create WAF rule to block attack
aws wafv2 create-rule \
  --name block-ddos \
  --scope REGIONAL \
  --priority 1 \
  --statement RateLimitStatement={Limit=100,AggregateKeyType=IP} \
  --action Block={}

# 4. Scale up infrastructure
kubectl scale deployment/<name> -n <namespace> --replicas=<higher-count>

# 5. Contact AWS Support for DDoS mitigation
```

### 5. Privilege Escalation

**Indicators:**
- Unusual IAM policy changes
- Role assumption from unexpected sources
- Elevated permissions granted
- GuardDuty PrivilegeEscalation findings

**Immediate Actions:**
```bash
# 1. Revoke assume role permissions
aws iam delete-role-policy --role-name <role> --policy-name <policy>

# 2. Review and revert IAM changes
aws iam list-policy-versions --policy-arn <policy-arn>
aws iam set-default-policy-version --policy-arn <policy-arn> --version-id <previous-version>

# 3. Audit all role assumptions
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-items 100

# 4. Enable CloudTrail Insights if not already
```

## Containment Procedures

### Isolate Affected Resources
```bash
# Move to quarantine security group
aws ec2 modify-instance-attribute \
  --instance-id <instance-id> \
  --groups <quarantine-sg-id>

# Disable network access
aws ec2 revoke-security-group-ingress \
  --group-id <sg-id> \
  --ip-permissions IpProtocol=-1,FromPort=-1,ToPort=-1,IpRanges='[{CidrIp=0.0.0.0/0}]'
```

### Preserve Evidence
```bash
# Snapshot volumes
aws ec2 create-snapshot --volume-id <volume-id> --description "Evidence"

# Export CloudTrail logs
aws cloudtrail lookup-events --output json > cloudtrail-evidence.json

# Export VPC Flow Logs
aws ec2 describe-flow-logs --filter Name=resource-id,Values=<vpc-id>
```

## Investigation

### Forensic Data Collection
```bash
# CloudTrail events
aws cloudtrail lookup-events \
  --start-time <time> \
  --end-time <time> \
  --max-items 1000 > events.json

# VPC Flow Logs
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs \
  --start-time <timestamp> \
  --end-time <timestamp> > flowlogs.json

# GuardDuty findings
aws guardduty list-findings \
  --detector-id <detector-id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' > guardduty.json

# Security Hub findings
aws securityhub get-findings \
  --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}' > securityhub.json
```

## Recovery

### Post-Incident Hardening
```bash
# 1. Rotate all credentials
# 2. Patch vulnerable systems
# 3. Update security groups
# 4. Enable additional logging
# 5. Implement additional monitoring
```

## Communication

### Security Incident Notification
```markdown
**🔐 SECURITY INCIDENT**

**Classification:** [Critical/High/Medium/Low]
**Type:** [Unauthorized Access/Data Breach/Malware/etc]
**Status:** Investigating
**Impact:** [Description]

**Actions Taken:**
- Affected systems isolated
- Credentials rotated
- Investigation initiated

**Current Status:** Contained

**Next Update:** [Time]

**DO NOT SHARE** - Confidential
```

## Compliance Requirements

### Breach Notification Requirements
- **GDPR:** 72 hours
- **CCPA:** Without unreasonable delay
- **HIPAA:** 60 days
- **PCI-DSS:** Immediately

### Documentation Required
- Timeline of events
- Systems affected
- Data accessed
- Users impacted
- Actions taken
- Lessons learned

## Post-Incident

### Security Review Checklist
- [ ] Root cause identified
- [ ] All compromised credentials rotated
- [ ] Vulnerable systems patched
- [ ] Security controls enhanced
- [ ] Monitoring improved
- [ ] Documentation updated
- [ ] Team training conducted
- [ ] Compliance notifications sent
- [ ] Insurance notified (if applicable)

## References

- AWS Security Best Practices
- CIS AWS Foundations Benchmark
- NIST Cybersecurity Framework
- Company Security Policy
