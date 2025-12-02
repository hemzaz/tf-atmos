# Deployment Procedures

## Overview

Standard deployment procedures for infrastructure and application changes.

## Pre-Deployment Checklist

- [ ] Changes reviewed and approved
- [ ] Tests passing (unit, integration, e2e)
- [ ] Staging deployment successful
- [ ] Rollback plan documented
- [ ] Monitoring configured
- [ ] Change window scheduled
- [ ] Stakeholders notified
- [ ] Backup verified
- [ ] Runbook updated

## Deployment Types

### 1. Terraform Infrastructure Changes

```bash
# Navigate to environment directory
cd stacks/deployments/<tenant>/<account>/<environment>

# Validate configuration
atmos workflow validate tenant=<tenant> account=<account> environment=<environment>

# Plan changes
atmos terraform plan <component> -s <stack>

# Review plan carefully
# Check for:
# - Unintended resource destruction
# - Security group changes
# - IAM policy changes
# - Data store modifications

# Apply changes
atmos terraform apply <component> -s <stack>

# Verify deployment
atmos terraform output <component> -s <stack>
```

### 2. Kubernetes Application Deployment

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Check current state
kubectl get deployments -n <namespace>
kubectl get pods -n <namespace>

# Update image tag in values.yaml or manifest
# Deploy using Helm
helm upgrade <release-name> <chart> \
  -n <namespace> \
  --set image.tag=<version> \
  --wait --timeout 10m

# OR kubectl apply
kubectl apply -f manifests/ -n <namespace>

# Watch rollout
kubectl rollout status deployment/<name> -n <namespace>

# Verify deployment
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod-name> --tail=50
```

### 3. Lambda Function Deployment

```bash
# Package function
cd lambda/<function-name>
zip -r function.zip .

# Update function code
aws lambda update-function-code \
  --function-name <function-name> \
  --zip-file fileb://function.zip

# Publish new version
aws lambda publish-version \
  --function-name <function-name>

# Update alias to new version
aws lambda update-alias \
  --function-name <function-name> \
  --name production \
  --function-version <version>

# Test function
aws lambda invoke \
  --function-name <function-name> \
  --payload '{"test": "data"}' \
  response.json
```

## Deployment Strategies

### Blue-Green Deployment

```bash
# Step 1: Deploy green environment
kubectl apply -f green-deployment.yaml

# Step 2: Wait for green to be healthy
kubectl wait --for=condition=available \
  deployment/app-green -n <namespace> --timeout=300s

# Step 3: Switch traffic
kubectl patch service app-service -n <namespace> \
  -p '{"spec":{"selector":{"version":"green"}}}'

# Step 4: Monitor for 15 minutes
# Step 5: If successful, scale down blue
kubectl scale deployment app-blue -n <namespace> --replicas=0
```

### Canary Deployment

```bash
# Step 1: Deploy canary with low replicas
kubectl apply -f canary-deployment.yaml

# Step 2: Monitor canary metrics
# Check error rates, latency, resource usage

# Step 3: Gradually increase canary traffic
# Update service weights or ingress rules
kubectl patch ingress <name> -n <namespace> \
  --type=json -p='[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/weight","value":10}]'

# Step 4: If metrics look good, continue to 50%, then 100%
# Step 5: Retire old version
```

### Rolling Update

```bash
# Configure rolling update strategy
kubectl patch deployment <name> -n <namespace> -p '{
  "spec": {
    "strategy": {
      "type": "RollingUpdate",
      "rollingUpdate": {
        "maxSurge": 1,
        "maxUnavailable": 0
      }
    }
  }
}'

# Deploy new version
kubectl set image deployment/<name> \
  <container>=<image>:<new-tag> -n <namespace>

# Watch rollout
kubectl rollout status deployment/<name> -n <namespace>
```

## Database Migrations

### Safe Migration Process

```bash
# Step 1: Backup database
aws rds create-db-snapshot \
  --db-instance-identifier <instance-id> \
  --db-snapshot-identifier pre-migration-$(date +%Y%m%d-%H%M%S)

# Step 2: Test migration on staging
# Run migration scripts

# Step 3: Schedule maintenance window
# Step 4: Enable read-only mode (if applicable)

# Step 5: Run migration
kubectl exec -it <pod-name> -n <namespace> -- \
  python manage.py migrate

# OR for Flyway
flyway -url=<jdbc-url> -user=<user> -password=<password> migrate

# Step 6: Verify migration
# Check schema version
# Run data validation queries

# Step 7: Disable read-only mode
# Step 8: Monitor application
```

## Post-Deployment Verification

### Health Checks

```bash
# 1. Check application health endpoints
for i in {1..5}; do
  curl -s https://<domain>/health | jq .
  sleep 2
done

# 2. Check pod status
kubectl get pods -n <namespace>

# 3. Check logs for errors
kubectl logs -n <namespace> -l app=<name> --tail=100 | grep -i error

# 4. Check metrics
kubectl top pods -n <namespace>

# 5. Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

### Smoke Tests

```bash
# Run automated smoke tests
npm run test:smoke -- --env=production

# Test critical user journeys:
# - User login
# - Main feature workflows
# - Payment processing (if applicable)
# - API endpoints
```

### Performance Validation

```bash
# Check response times
ab -n 1000 -c 10 https://<domain>/api/endpoint

# Check database performance
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average
```

## Rollback Decision Criteria

**Rollback if:**
- Error rate > 5%
- P95 latency increased > 50%
- Critical functionality broken
- Data corruption detected
- Security vulnerability introduced
- Database migration failed

**Continue monitoring if:**
- Minor cosmetic issues
- Non-critical features affected
- Error rate < 1%
- Performance within acceptable range

## Communication

### Deployment Announcement Template

```markdown
**Deployment Notification**

**Environment:** Production
**Date/Time:** YYYY-MM-DD HH:MM UTC
**Duration:** ~30 minutes
**Impact:** No expected downtime

**Changes:**
- [Feature 1]
- [Bug fix 2]
- [Infrastructure update 3]

**Rollback Plan:** [Link to runbook]

**Monitoring:** [Link to dashboard]

Questions? #engineering-deployments
```

### Post-Deployment Summary

```markdown
**Deployment Complete**

**Status:** ✅ Success / ⚠️ Partial / ❌ Rolled Back
**Duration:** X minutes
**Issues:** None / [Description]

**Metrics:**
- Error rate: 0.1%
- Latency P95: 250ms
- CPU usage: 45%
- Memory usage: 60%

**Next Steps:** [Any follow-up actions]
```

## Emergency Procedures

### Deployment Freeze

```bash
# Lock Terraform state
terraform state lock <lock-id>

# Disable auto-deployment pipeline
# Update CI/CD configuration

# Communicate freeze
# Post in #engineering-announcements
```

### Hotfix Deployment

```bash
# 1. Create hotfix branch
git checkout -b hotfix/critical-bug main

# 2. Make minimal changes
# 3. Fast-track review
# 4. Deploy to staging
# 5. Deploy to production immediately
# 6. Monitor closely
# 7. Create postmortem
```

## References

- [Rollback Procedures](/docs/runbooks/rollback-procedures.md)
- [Incident Response](/docs/runbooks/incident-response.md)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs)
