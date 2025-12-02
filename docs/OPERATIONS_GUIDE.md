# Operations Guide

Complete guide for daily operations, maintenance, and troubleshooting of the Terraform/Atmos infrastructure platform.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Weekly Tasks](#weekly-tasks)
3. [Monthly Tasks](#monthly-tasks)
4. [Scaling Procedures](#scaling-procedures)
5. [Upgrade Procedures](#upgrade-procedures)
6. [Backup & Restore](#backup--restore)
7. [Security Operations](#security-operations)
8. [Cost Optimization](#cost-optimization)
9. [Incident Response](#incident-response)
10. [Maintenance Windows](#maintenance-windows)

---

## Daily Operations

### Morning Health Checks

Run these checks every morning to ensure system health:

```bash
# 1. Check all stack health
atmos workflow validate

# 2. Review CloudWatch dashboards
open https://console.aws.amazon.com/cloudwatch/

# 3. Check EKS cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# 4. Review recent deployments
kubectl get deployments --all-namespaces -o wide

# 5. Check RDS instances
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table

# 6. Review cost anomalies
aws ce get-anomalies --start-date $(date -d '1 day ago' +%Y-%m-%d) --end-date $(date +%Y-%m-%d)
```

### Monitoring Checks

```bash
# Check for CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM

# Review EKS cluster metrics
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory

# Check application logs
kubectl logs -f -l app=myapp --tail=100

# Review API Gateway metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=my-api \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Log Review

```bash
# Review EKS cluster logs
aws logs tail /aws/eks/$(kubectl config current-context | cut -d'/' -f2)/cluster --follow --since 1h

# Check application logs
kubectl logs -l app=myapp --tail=100 --all-containers=true

# Review Lambda function logs
aws logs tail /aws/lambda/my-function --follow --since 1h

# Check VPC Flow Logs
aws logs tail /aws/vpc/flowlogs --since 1h
```

### Performance Checks

```bash
# Check node resource usage
kubectl describe nodes | grep -A 5 "Allocated resources"

# Review pod resource limits
kubectl get pods --all-namespaces -o json | \
  jq '.items[] | {name: .metadata.name, namespace: .metadata.namespace, resources: .spec.containers[].resources}'

# Check database performance
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=my-database \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

## Weekly Tasks

### Monday: Security Review

```bash
# Review GuardDuty findings
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

# Check AWS Config compliance
aws configservice describe-compliance-by-config-rule

# Review IAM access advisor
aws iam generate-service-last-accessed-details \
  --arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/my-role

# Scan for unused security groups
aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[0]==null]'

# Review Secrets Manager secrets
aws secretsmanager list-secrets --query 'SecretList[*].[Name,LastAccessedDate]' --output table
```

### Tuesday: Backup Verification

```bash
# Verify RDS snapshots
aws rds describe-db-snapshots \
  --query 'DBSnapshots[?SnapshotCreateTime>=`'$(date -d '7 days ago' +%Y-%m-%d)'`]'

# Check Velero backups (EKS)
kubectl get backups -n velero

# Verify S3 bucket replication
aws s3api get-bucket-replication --bucket my-bucket

# Test restore procedure (in test environment)
velero restore create --from-backup my-backup-20250101
```

### Wednesday: Performance Review

```bash
# Generate performance report
./scripts/generate-performance-report.sh

# Review slow queries (RDS)
aws rds describe-db-log-files --db-instance-identifier my-database
aws rds download-db-log-file-portion \
  --db-instance-identifier my-database \
  --log-file-name slowquery/mysql-slowquery.log

# Check API latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Latency \
  --dimensions Name=ApiName,Value=my-api \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average,Maximum

# Review EKS pod autoscaling
kubectl get hpa --all-namespaces
```

### Thursday: Cost Review

```bash
# Generate weekly cost report
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Check for underutilized resources
./scripts/find-underutilized-resources.sh

# Review Reserved Instance utilization
aws ce get-reservation-utilization \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)

# Identify cost anomalies
aws ce get-anomalies \
  --date-interval Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)
```

### Friday: Infrastructure Drift Detection

```bash
# Run drift detection workflow
atmos workflow drift-detection tenant=mycompany account=dev environment=use1

# Review drift report
cat .atmos/drift-report-$(date +%Y%m%d).json

# Check for manual changes
aws config select-resource-config \
  --expression "SELECT resourceId, resourceType WHERE tags.tag = 'ManagedBy' AND tags.value != 'terraform'"

# Reconcile drift
# If drift is acceptable:
terraform refresh

# If drift should be corrected:
atmos terraform apply <component> -s <stack>
```

---

## Monthly Tasks

### First of Month: Security Audit

```bash
# Full security audit
./scripts/security-audit.sh

# Review IAM policies
aws iam get-account-authorization-details > iam-audit-$(date +%Y%m).json

# Check for over-privileged roles
./scripts/check-iam-permissions.sh --audit

# Rotate secrets
./scripts/rotate-secrets.sh

# Review SSL certificates
aws acm list-certificates --query 'CertificateSummaryList[?NotAfter<`'$(date -d '+30 days' +%Y-%m-%d)'`]'
```

### Mid-Month: Capacity Planning

```bash
# Generate capacity report
./scripts/capacity-planning-report.sh

# Review node group scaling
aws eks describe-nodegroup --cluster-name my-cluster --nodegroup-name my-nodegroup

# Check RDS storage
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,AllocatedStorage,MaxAllocatedStorage]'

# Review S3 bucket sizes
aws s3 ls --summarize --recursive s3://my-bucket

# Forecast next month costs
aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-01),End=$(date -d '+1 month' +%Y-%m-01) \
  --metric BLENDED_COST \
  --granularity MONTHLY
```

### End of Month: Compliance & Reporting

```bash
# Generate compliance report
aws configservice describe-compliance-by-config-rule > compliance-$(date +%Y%m).json

# Create monthly summary
./scripts/generate-monthly-report.sh

# Review and document incidents
./scripts/incident-summary.sh --month $(date +%Y-%m)

# Update runbooks with lessons learned
vim docs/operations/runbooks/$(date +%Y-%m)-updates.md
```

---

## Scaling Procedures

### Scale EKS Node Groups

```bash
# Scale up node group
aws eks update-nodegroup-config \
  --cluster-name my-cluster \
  --nodegroup-name my-nodegroup \
  --scaling-config minSize=5,maxSize=20,desiredSize=10

# Monitor scaling
watch -n 5 kubectl get nodes

# Verify new nodes
kubectl get nodes -o wide
```

### Scale Application Workloads

```bash
# Scale deployment
kubectl scale deployment my-app --replicas=10

# Configure HPA
kubectl autoscale deployment my-app --min=3 --max=20 --cpu-percent=70

# Verify HPA
kubectl get hpa my-app --watch
```

### Scale RDS Database

```bash
# Modify instance class
aws rds modify-db-instance \
  --db-instance-identifier my-database \
  --db-instance-class db.r5.2xlarge \
  --apply-immediately

# Monitor modification
aws rds describe-db-instances \
  --db-instance-identifier my-database \
  --query 'DBInstances[0].DBInstanceStatus'

# Add read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier my-database-replica \
  --source-db-instance-identifier my-database
```

### Scale Infrastructure Components

```bash
# Update Terraform configuration
vim stacks/orgs/mycompany/dev/use1/eks.yaml

# Plan changes
atmos terraform plan eks -s mycompany-dev-use1

# Apply scaling changes
atmos terraform apply eks -s mycompany-dev-use1

# Verify scaling
kubectl get nodes
aws eks describe-nodegroup --cluster-name my-cluster --nodegroup-name my-nodegroup
```

---

## Upgrade Procedures

### Upgrade EKS Cluster

```bash
# Check current version
kubectl version --short

# Plan upgrade
atmos terraform plan eks -s mycompany-dev-use1 \
  -var='kubernetes_version=1.29'

# Upgrade control plane (15-20 minutes)
atmos terraform apply eks -s mycompany-dev-use1 \
  -var='kubernetes_version=1.29'

# Wait for control plane upgrade
aws eks wait cluster-active --name my-cluster

# Upgrade node groups (one at a time)
for ng in system application; do
  aws eks update-nodegroup-version \
    --cluster-name my-cluster \
    --nodegroup-name $ng \
    --kubernetes-version 1.29

  aws eks wait nodegroup-active \
    --cluster-name my-cluster \
    --nodegroup-name $ng
done

# Upgrade add-ons
kubectl apply -f https://raw.githubusercontent.com/aws/aws-load-balancer-controller/v2.6.0/docs/install/v2_6_0_full.yaml

# Verify upgrade
kubectl version
kubectl get nodes
```

### Upgrade Terraform Components

```bash
# Update component version
vim components/terraform/<component>/versions.tf

# Test in dev environment first
atmos terraform plan <component> -s mycompany-dev-use1

# Apply to dev
atmos terraform apply <component> -s mycompany-dev-use1

# Verify functionality
./scripts/smoke-test.sh

# Roll out to staging
atmos terraform apply <component> -s mycompany-staging-use1

# Roll out to production (with approval)
atmos terraform apply <component> -s mycompany-prod-use1
```

### Upgrade Application Workloads

```bash
# Rolling update
kubectl set image deployment/my-app my-app=myapp:v2.0.0

# Monitor rollout
kubectl rollout status deployment/my-app

# Rollback if needed
kubectl rollout undo deployment/my-app

# Blue/green deployment
kubectl apply -f manifests/my-app-v2.yaml
# Test v2
# Switch traffic
kubectl patch service my-app -p '{"spec":{"selector":{"version":"v2"}}}'
```

---

## Backup & Restore

### Backup Operations

```bash
# Manual RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier my-database \
  --db-snapshot-identifier my-database-$(date +%Y%m%d-%H%M%S)

# Manual Velero backup
velero backup create my-backup-$(date +%Y%m%d) \
  --include-namespaces default,production

# Backup Terraform state
aws s3 cp \
  s3://terraform-state-${AWS_ACCOUNT_ID}/ \
  s3://terraform-state-backup-${AWS_ACCOUNT_ID}/ \
  --recursive

# Export cluster configuration
kubectl get all --all-namespaces -o yaml > cluster-backup-$(date +%Y%m%d).yaml
```

### Restore Operations

```bash
# Restore RDS from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier my-database-restored \
  --db-snapshot-identifier my-database-20250101

# Restore Velero backup
velero restore create --from-backup my-backup-20250101

# Restore Terraform state
aws s3 cp \
  s3://terraform-state-backup-${AWS_ACCOUNT_ID}/vpc/terraform.tfstate \
  s3://terraform-state-${AWS_ACCOUNT_ID}/vpc/terraform.tfstate
```

---

## Security Operations

### Certificate Rotation

```bash
# Check certificate expiration
aws acm list-certificates --query 'CertificateSummaryList[*].[DomainName,NotAfter]' --output table

# Rotate certificate using workflow
atmos workflow rotate-certificate \
  tenant=mycompany \
  account=prod \
  environment=use1 \
  certificate_name=*.example.com

# Verify new certificate
aws acm describe-certificate --certificate-arn <new-cert-arn>
```

### Secret Rotation

```bash
# Rotate RDS password
./scripts/rotate-rds-password.sh --database my-database

# Rotate API keys
./scripts/rotate-api-keys.sh

# Update Kubernetes secrets
kubectl create secret generic my-secret \
  --from-literal=password=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to use new secrets
kubectl rollout restart deployment/my-app
```

### Access Review

```bash
# List IAM users
aws iam list-users --output table

# Review user access
aws iam get-user-policy --user-name myuser --policy-name mypolicy

# Remove inactive users
aws iam delete-user --user-name inactive-user

# Review kubectl access
kubectl get clusterrolebindings
kubectl get rolebindings --all-namespaces
```

---

## Cost Optimization

### Identify Cost Savings

```bash
# Find unused EBS volumes
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[*].[VolumeId,Size,VolumeType]' \
  --output table

# Find unattached elastic IPs
aws ec2 describe-addresses \
  --filters "Name=association-id,Values=null" \
  --query 'Addresses[*].[PublicIp,AllocationId]' \
  --output table

# Find old snapshots
aws ec2 describe-snapshots \
  --owner-ids ${AWS_ACCOUNT_ID} \
  --query 'Snapshots[?StartTime<=`'$(date -d '90 days ago' +%Y-%m-%d)'`]'

# Review idle load balancers
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?State.Code==`active`]' | \
  jq -r '.[] | select(.Scheme=="internet-facing") | .LoadBalancerArn' | \
  while read lb; do
    aws cloudwatch get-metric-statistics \
      --namespace AWS/ApplicationELB \
      --metric-name RequestCount \
      --dimensions Name=LoadBalancer,Value=${lb##*/} \
      --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 604800 \
      --statistics Sum
  done
```

### Implement Cost Savings

```bash
# Delete unused volumes
aws ec2 delete-volume --volume-id vol-xxxxxxxxx

# Release unattached IPs
aws ec2 release-address --allocation-id eipalloc-xxxxxxxxx

# Delete old snapshots
./scripts/cleanup-old-snapshots.sh --days 90

# Enable S3 Intelligent Tiering
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket my-bucket \
  --id intelligent-tiering \
  --intelligent-tiering-configuration file://tiering-config.json
```

---

## Incident Response

### Incident Response Checklist

1. [ ] Identify and assess the issue
2. [ ] Notify stakeholders
3. [ ] Create incident ticket
4. [ ] Isolate affected components
5. [ ] Collect logs and diagnostics
6. [ ] Implement fix or workaround
7. [ ] Verify resolution
8. [ ] Document incident
9. [ ] Conduct post-mortem
10. [ ] Implement preventive measures

### Emergency Procedures

```bash
# High CPU on EKS nodes
kubectl top nodes
kubectl get pods --all-namespaces --sort-by=.spec.nodeName
kubectl describe node <high-cpu-node>
# Scale out node group if needed
aws eks update-nodegroup-config --cluster-name my-cluster --nodegroup-name my-nodegroup --scaling-config desiredSize=10

# Database performance issues
aws rds describe-db-instances --db-instance-identifier my-database
aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name CPUUtilization ...
# Scale up database if needed
aws rds modify-db-instance --db-instance-identifier my-database --db-instance-class db.r5.2xlarge

# Application not responding
kubectl get pods -l app=myapp
kubectl logs -l app=myapp --tail=100
kubectl describe pod <pod-name>
# Restart if needed
kubectl rollout restart deployment/myapp

# Network connectivity issues
kubectl run test-pod --image=nicolaka/netshoot -it --rm -- bash
# Test from pod
curl -v https://api.example.com
nslookup api.example.com
traceroute api.example.com
```

---

## Maintenance Windows

### Schedule Maintenance

```bash
# Notify users
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:${AWS_ACCOUNT_ID}:maintenance-alerts \
  --message "Scheduled maintenance on $(date -d '+1 week' +%Y-%m-%d) at 02:00 UTC"

# Create maintenance calendar event
# Update status page
# Prepare rollback plan
```

### Execute Maintenance

```bash
# Enable maintenance mode
kubectl apply -f manifests/maintenance-page.yaml

# Stop auto-scaling
kubectl patch hpa myapp -p '{"spec":{"minReplicas":0,"maxReplicas":0}}'

# Perform maintenance tasks
# ... upgrade, patch, configure ...

# Verify functionality
./scripts/smoke-test.sh

# Disable maintenance mode
kubectl delete -f manifests/maintenance-page.yaml

# Re-enable auto-scaling
kubectl patch hpa myapp -p '{"spec":{"minReplicas":3,"maxReplicas":20}}'
```

---

## Useful Commands Reference

### Quick Diagnostics

```bash
# Check all infrastructure health
./scripts/health-check.sh

# View all stack outputs
./scripts/list_stacks.sh

# Get component status
atmos describe component <component> -s <stack>

# Export all configurations
atmos describe stacks --format=json > stacks-$(date +%Y%m%d).json
```

### Automation Scripts

All operational scripts are in `/scripts/`:

- `health-check.sh` - Complete health check
- `backup-all.sh` - Backup all components
- `cost-report.sh` - Generate cost report
- `security-audit.sh` - Security audit
- `performance-report.sh` - Performance analysis
- `cleanup-resources.sh` - Remove unused resources

---

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**On-Call Contact**: platform-team@example.com
**Emergency Escalation**: See [Incident Response Playbook](./operations/incident-response.md)
