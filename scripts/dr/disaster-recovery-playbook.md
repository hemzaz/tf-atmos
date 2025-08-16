# IDP Platform Disaster Recovery Playbook

## Overview

This playbook provides step-by-step procedures for disaster recovery scenarios for the Internal Developer Platform. It covers different types of disasters and their appropriate response procedures.

## Emergency Contacts

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| Platform Lead | John Doe | +1-555-0101 | john.doe@company.com |
| SRE On-Call | On-Call Rotation | +1-555-0911 | sre-oncall@company.com |
| Security Team | Jane Smith | +1-555-0102 | security@company.com |
| Infrastructure Lead | Bob Johnson | +1-555-0103 | bob.johnson@company.com |

## Disaster Types and RTOs/RPOs

| Disaster Type | RTO (Recovery Time Objective) | RPO (Recovery Point Objective) |
|---------------|------------------------------|--------------------------------|
| Application Failure | 15 minutes | 5 minutes |
| Database Corruption | 1 hour | 15 minutes |
| Complete Cluster Loss | 4 hours | 1 hour |
| Multi-Region Outage | 8 hours | 4 hours |
| Data Center Disaster | 24 hours | 1 hour |

## Pre-Disaster Checklist

- [ ] All backup procedures are running successfully
- [ ] Disaster recovery environment is provisioned and tested
- [ ] All team members have access to emergency procedures
- [ ] Communication channels are established and tested
- [ ] Runbooks are up-to-date and accessible

## Incident Response Procedures

### 1. Initial Assessment and Communication

#### Step 1: Incident Detection and Initial Response
```bash
# Check overall platform health
curl -f https://platform.company.com/health || echo "Platform DOWN"

# Check individual services
kubectl get pods -n idp-system
kubectl get services -n idp-system

# Check monitoring dashboards
# - Grafana: https://grafana.platform.company.com
# - Prometheus: https://prometheus.platform.company.com
```

#### Step 2: Incident Classification
Classify the incident based on severity:

**P0 - Critical (Complete Service Outage)**
- Platform completely inaccessible
- Data loss or corruption
- Security breach

**P1 - High (Major Functionality Impaired)**
- Core features unavailable
- Significant performance degradation
- Some users unable to access platform

**P2 - Medium (Minor Functionality Impaired)**
- Non-critical features affected
- Workarounds available
- Limited user impact

**P3 - Low (Minimal Impact)**
- Cosmetic issues
- Non-essential features affected
- No user impact

#### Step 3: Incident Communication
```bash
# Send initial incident notification
./scripts/dr/send-incident-alert.sh \
  --severity="P0" \
  --title="IDP Platform Outage" \
  --description="Platform is completely inaccessible" \
  --incident-commander="john.doe@company.com"
```

### 2. Application-Level Disasters

#### Scenario: Backstage Service Failure

**Symptoms:**
- Backstage UI inaccessible
- HTTP 5xx errors
- Pod crashes or restarts

**Recovery Steps:**
```bash
# 1. Check pod status
kubectl get pods -n idp-system -l app.kubernetes.io/component=backstage

# 2. Check logs
kubectl logs -n idp-system -l app.kubernetes.io/component=backstage --tail=100

# 3. Check resource usage
kubectl top pods -n idp-system -l app.kubernetes.io/component=backstage

# 4. Restart deployment if needed
kubectl rollout restart deployment/idp-platform-backstage -n idp-system

# 5. Scale up if resource constrained
kubectl scale deployment/idp-platform-backstage --replicas=5 -n idp-system

# 6. Verify recovery
kubectl rollout status deployment/idp-platform-backstage -n idp-system
curl -f https://platform.company.com/health
```

#### Scenario: Platform API Service Failure

**Recovery Steps:**
```bash
# 1. Check API health
curl -f https://api.platform.company.com/health

# 2. Check pod status and logs
kubectl get pods -n idp-system -l app.kubernetes.io/component=platform-api
kubectl logs -n idp-system -l app.kubernetes.io/component=platform-api --tail=100

# 3. Check database connectivity
kubectl exec -n idp-system deployment/idp-platform-platform-api -- \
  pg_isready -h $(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.host}' | base64 -d)

# 4. Check Redis connectivity
kubectl exec -n idp-system deployment/idp-platform-platform-api -- \
  redis-cli -h $(kubectl get secret redis-credentials -n idp-system -o jsonpath='{.data.host}' | base64 -d) ping

# 5. Restart if needed
kubectl rollout restart deployment/idp-platform-platform-api -n idp-system
```

### 3. Database Disasters

#### Scenario: PostgreSQL Database Failure

**Recovery Steps:**
```bash
# 1. Check database status
kubectl exec -n idp-system deployment/idp-platform-postgresql -- pg_isready

# 2. Check for corruption
kubectl exec -n idp-system deployment/idp-platform-postgresql -- \
  psql -c "SELECT datname, pg_database_size(datname) FROM pg_database;"

# 3. If corruption detected, restore from backup
./scripts/dr/restore-database.sh --type=postgresql --restore-point=latest

# 4. Verify database integrity after restore
kubectl exec -n idp-system deployment/idp-platform-postgresql -- \
  psql -d backstage -c "SELECT COUNT(*) FROM information_schema.tables;"

# 5. Restart dependent services
kubectl rollout restart deployment/idp-platform-backstage -n idp-system
kubectl rollout restart deployment/idp-platform-platform-api -n idp-system
```

#### Scenario: Redis Cache Failure

**Recovery Steps:**
```bash
# 1. Check Redis status
kubectl exec -n idp-system deployment/idp-platform-redis -- redis-cli ping

# 2. Check memory usage and configuration
kubectl exec -n idp-system deployment/idp-platform-redis -- redis-cli info memory

# 3. If Redis is down, restart
kubectl rollout restart deployment/idp-platform-redis -n idp-system

# 4. If data corruption, restore from backup
./scripts/dr/restore-database.sh --type=redis --restore-point=latest

# 5. Clear application caches to rebuild
kubectl exec -n idp-system deployment/idp-platform-platform-api -- \
  curl -X POST http://localhost:8000/admin/cache/clear
```

### 4. Complete Cluster Disaster

#### Scenario: Kubernetes Cluster Total Loss

**Recovery Steps:**

1. **Provision New Cluster**
```bash
# Deploy new EKS cluster using Terraform
cd infrastructure/terraform
terraform plan -var="cluster_name=idp-recovery-cluster"
terraform apply -auto-approve

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name idp-recovery-cluster
```

2. **Restore Infrastructure Components**
```bash
# Install essential operators
kubectl apply -f https://github.com/external-secrets/external-secrets/releases/latest/download/bundle.yaml
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/bundle.yaml

# Install Velero for backup restoration
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.0 \
    --bucket idp-platform-backups \
    --secret-file ./credentials \
    --backup-location-config region=us-east-1
```

3. **Restore from Velero Backup**
```bash
# List available backups
velero backup get

# Restore latest full backup
LATEST_BACKUP=$(velero backup get --output json | jq -r '.items[0].metadata.name')
velero restore create recovery-restore --from-backup $LATEST_BACKUP --wait

# Verify restoration
kubectl get pods --all-namespaces
kubectl get pvc --all-namespaces
```

4. **Restore Databases**
```bash
# Restore PostgreSQL
./scripts/dr/restore-database.sh --type=postgresql --restore-point=latest

# Restore Redis
./scripts/dr/restore-database.sh --type=redis --restore-point=latest
```

5. **Update DNS and Load Balancer**
```bash
# Get new load balancer endpoint
NEW_LB=$(kubectl get svc -n idp-system idp-platform-backstage -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update Route53 records
aws route53 change-resource-record-sets \
    --hosted-zone-id Z123456789 \
    --change-batch file://dns-update.json
```

6. **Verify Full Recovery**
```bash
# Test all endpoints
curl -f https://platform.company.com/health
curl -f https://api.platform.company.com/health
curl -f https://grafana.platform.company.com/api/health

# Run end-to-end tests
./tests/e2e/run-tests.sh --environment=production
```

### 5. Multi-Region Disaster

#### Scenario: Primary AWS Region Failure

**Recovery Steps:**

1. **Activate DR Region Infrastructure**
```bash
# Switch to DR region
export AWS_DEFAULT_REGION=us-west-2

# Deploy infrastructure in DR region
cd infrastructure/terraform
terraform workspace select dr-region
terraform apply -auto-approve
```

2. **Restore Data to DR Region**
```bash
# Restore database from cross-region backup
./scripts/dr/cross-region-restore.sh \
    --source-region=us-east-1 \
    --target-region=us-west-2 \
    --restore-point=latest

# Verify data integrity
./scripts/dr/verify-data-integrity.sh
```

3. **Update Global DNS**
```bash
# Update Route53 health checks and failover
aws route53 change-resource-record-sets \
    --hosted-zone-id Z123456789 \
    --change-batch file://failover-to-dr.json

# Verify DNS propagation
dig platform.company.com
```

4. **Validate DR Environment**
```bash
# Run comprehensive health checks
./scripts/dr/health-check.sh --region=us-west-2 --comprehensive

# Run smoke tests
./tests/smoke/run-smoke-tests.sh --environment=dr
```

## Recovery Validation Procedures

### Post-Recovery Checklist

- [ ] All services are healthy and responding
- [ ] Database integrity verified
- [ ] User authentication working
- [ ] Monitoring and alerting functional
- [ ] Backup procedures resumed
- [ ] Performance metrics within normal ranges
- [ ] End-to-end tests passing

### Validation Scripts

```bash
# Run comprehensive validation
./scripts/dr/validate-recovery.sh

# Check data consistency
./scripts/dr/data-consistency-check.sh

# Performance baseline test
./scripts/dr/performance-test.sh
```

## Post-Incident Procedures

### 1. Document the Incident

Create an incident report including:
- Timeline of events
- Root cause analysis
- Actions taken
- Lessons learned
- Preventive measures

### 2. Update Runbooks

- Update this playbook with lessons learned
- Improve automation scripts
- Update contact information
- Review and update RTOs/RPOs

### 3. Test Improvements

- Schedule chaos engineering exercises
- Test updated procedures
- Validate backup and restore processes
- Train team on new procedures

## Preventive Measures

### Regular Testing

1. **Monthly DR Drills**
   - Test backup restoration procedures
   - Validate failover mechanisms
   - Update documentation

2. **Quarterly Chaos Engineering**
   - Simulate different failure scenarios
   - Test monitoring and alerting
   - Validate team response procedures

3. **Annual DR Simulation**
   - Full-scale disaster simulation
   - Multi-team coordination exercise
   - External communication testing

### Monitoring and Alerting

- Continuous health monitoring
- Proactive alerting on anomalies
- Automated backup validation
- Capacity planning and monitoring

### Backup Strategy

- Multiple backup types (full, incremental, differential)
- Cross-region backup replication
- Regular restore testing
- Automated backup validation

## Appendix

### A. Emergency Procedures Quick Reference

| Scenario | Command | Expected Outcome |
|----------|---------|------------------|
| Service Down | `kubectl rollout restart deployment/<name>` | Pods recreated |
| DB Connection Issues | `kubectl port-forward svc/postgresql 5432:5432` | Local DB access |
| Check Logs | `kubectl logs -f deployment/<name>` | Real-time logs |
| Scale Up | `kubectl scale deployment/<name> --replicas=5` | More pods created |

### B. Important File Locations

- Backup scripts: `/scripts/dr/`
- Configuration files: `/k8s/config/`
- Terraform modules: `/infrastructure/terraform/`
- Monitoring configs: `/monitoring/`

### C. External Dependencies

- AWS Services (EKS, RDS, ElastiCache, S3, Route53)
- GitHub (source code, CI/CD)
- External monitoring services
- Third-party integrations

---

**Last Updated:** $(date +%Y-%m-%d)  
**Version:** 1.0  
**Owner:** Platform Engineering Team