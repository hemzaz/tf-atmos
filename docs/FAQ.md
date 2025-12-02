# Frequently Asked Questions (FAQ)

## Table of Contents

- [Getting Started](#getting-started)
- [Infrastructure Management](#infrastructure-management)
- [Deployment & Operations](#deployment--operations)
- [Troubleshooting](#troubleshooting)
- [Cost & Billing](#cost--billing)
- [Security](#security)
- [Scaling](#scaling)
- [Disaster Recovery](#disaster-recovery)

---

## Getting Started

### What is this project?

This is a Terraform/Atmos infrastructure-as-code platform that provides:
- 17 production-ready Terraform components (VPC, EKS, RDS, Lambda, etc.)
- 16 automated workflows for common operations
- Multi-tenant architecture supporting multiple organizations and environments
- Python CLI (Gaia) for simplified operations
- Built-in monitoring, security, and cost optimization

### What are the prerequisites?

You need:
- AWS account with administrator access
- Terraform 1.11.0+
- Atmos CLI 1.163.0+
- Python 3.11+
- AWS CLI 2.0+
- kubectl 1.28+ (for EKS clusters)

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md#prerequisites) for detailed setup.

### How long does initial setup take?

- Tool installation: 15-30 minutes
- Backend initialization: 5-10 minutes
- VPC deployment: 5-10 minutes
- EKS cluster deployment: 15-20 minutes
- Complete environment: 45-60 minutes

### Where should I start?

1. Read the [README.md](../README.md) for overview
2. Follow [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for setup
3. Review [OPERATIONS_GUIDE.md](./OPERATIONS_GUIDE.md) for daily operations
4. Check component-specific docs in `/components/terraform/*/README.md`

---

## Infrastructure Management

### How do I deploy to a new region?

```bash
# 1. Create new environment configuration
./scripts/create-environment.sh \
  --tenant mycompany \
  --account prod \
  --environment usw2 \
  --region us-west-2 \
  --vpc-cidr 10.10.0.0/16

# 2. Review generated configuration
cat stacks/orgs/mycompany/prod/us-west-2/usw2/main.yaml

# 3. Deploy infrastructure
atmos workflow apply-environment \
  tenant=mycompany \
  account=prod \
  environment=usw2

# 4. Verify deployment
atmos terraform output vpc -s mycompany-prod-usw2
```

### How do I add a new tenant?

```bash
# 1. Create tenant directory structure
mkdir -p stacks/orgs/newtenant/{dev,staging,prod}

# 2. Copy tenant template
cp -r stacks/orgs/_template/* stacks/orgs/newtenant/

# 3. Update tenant configuration
vim stacks/orgs/newtenant/tenant.yaml

# 4. Create first environment
./scripts/create-environment.sh \
  --tenant newtenant \
  --account dev \
  --environment dev-01 \
  --vpc-cidr 10.20.0.0/16

# 5. Deploy tenant infrastructure
atmos workflow onboard-environment \
  tenant=newtenant \
  account=dev \
  environment=dev-01 \
  vpc_cidr=10.20.0.0/16
```

### How do I upgrade Terraform version?

```bash
# 1. Update version requirement in components
vim components/terraform/_base/versions.tf
# Change: required_version = ">= 1.11.0"

# 2. Update local Terraform
brew upgrade terraform
terraform version  # Verify

# 3. Test in dev environment
cd components/terraform/vpc
terraform init -upgrade
atmos terraform plan vpc -s mycompany-dev-use1

# 4. Apply to all environments gradually
atmos terraform init vpc -s mycompany-dev-use1 -upgrade
atmos terraform init vpc -s mycompany-staging-use1 -upgrade
atmos terraform init vpc -s mycompany-prod-use1 -upgrade
```

### How do I upgrade Atmos version?

```bash
# 1. Backup current configuration
cp .atmos.yaml .atmos.yaml.backup

# 2. Upgrade Atmos
brew upgrade cloudposse/tap/atmos

# 3. Verify version
atmos version

# 4. Test with validation
atmos workflow validate

# 5. Check for breaking changes
atmos describe stacks --format=json > stacks-new.json
diff stacks-old.json stacks-new.json
```

### What's the recommended CIDR allocation strategy?

Use non-overlapping ranges for each environment:

```yaml
# Development: 10.0.0.0/8 range
dev-01:  10.0.0.0/16   (65,536 IPs)
dev-02:  10.1.0.0/16   (65,536 IPs)

# Staging: 10.10.0.0/8 range
stg-01:  10.10.0.0/16  (65,536 IPs)
stg-02:  10.11.0.0/16  (65,536 IPs)

# Production: 10.20.0.0/8 range
prod-01: 10.20.0.0/16  (65,536 IPs)
prod-02: 10.21.0.0/16  (65,536 IPs)

# Within each VPC:
# - Public subnets:    x.x.1.0/24, x.x.2.0/24, x.x.3.0/24
# - Private subnets:   x.x.10.0/24, x.x.11.0/24, x.x.12.0/24
# - Database subnets:  x.x.20.0/24, x.x.21.0/24, x.x.22.0/24
```

---

## Deployment & Operations

### How do I troubleshoot deployment failures?

```bash
# 1. Enable debug logging
export TF_LOG=DEBUG
export ATMOS_LOGS_LEVEL=Debug

# 2. Check Terraform state
atmos terraform state list <component> -s <stack>

# 3. Review CloudWatch logs
aws logs tail /aws/terraform/<component> --follow

# 4. Validate configuration
atmos terraform validate <component> -s <stack>

# 5. Check for drift
atmos workflow drift-detection tenant=<tenant> account=<account> environment=<env>

# 6. Review specific error
atmos terraform plan <component> -s <stack> 2>&1 | tee plan-error.log
```

See [TROUBLESHOOTING.md](./operations/TROUBLESHOOTING.md) for common issues.

### How do I restore from backup?

**RDS Database:**
```bash
# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier my-database

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier my-database-restored \
  --db-snapshot-identifier my-snapshot-20250101

# Update application to use new endpoint
kubectl set env deployment/myapp \
  DATABASE_HOST=my-database-restored.xxxx.us-east-1.rds.amazonaws.com
```

**Kubernetes Cluster (Velero):**
```bash
# List backups
velero backup get

# Restore specific backup
velero restore create --from-backup my-backup-20250101

# Monitor restore
velero restore describe my-restore
```

**Terraform State:**
```bash
# List state versions
aws s3api list-object-versions \
  --bucket terraform-state-${AWS_ACCOUNT_ID} \
  --prefix vpc/terraform.tfstate

# Restore specific version
aws s3api get-object \
  --bucket terraform-state-${AWS_ACCOUNT_ID} \
  --key vpc/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.restored
```

### How do I scale up/down infrastructure?

**Scale EKS Node Groups:**
```bash
# Update configuration
vim stacks/orgs/mycompany/prod/us-east-1/use1/eks.yaml

# Change:
node_groups:
  application:
    desired_size: 10  # Increase from 5
    min_size: 5       # Increase from 3
    max_size: 30      # Increase from 20

# Apply changes
atmos terraform apply eks -s mycompany-prod-use1

# Or use AWS CLI for immediate scaling:
aws eks update-nodegroup-config \
  --cluster-name prod-use1-primary \
  --nodegroup-name application \
  --scaling-config minSize=5,maxSize=30,desiredSize=10
```

**Scale Application Pods:**
```bash
# Manual scaling
kubectl scale deployment myapp --replicas=10

# Horizontal Pod Autoscaler
kubectl autoscale deployment myapp \
  --min=3 --max=20 --cpu-percent=70
```

**Scale RDS:**
```bash
# Update configuration
vim stacks/orgs/mycompany/prod/us-east-1/use1/rds.yaml

# Change instance class
instance_class: db.r5.2xlarge  # Up from db.r5.xlarge

# Apply changes (requires downtime)
atmos terraform apply rds -s mycompany-prod-use1
```

### How do I upgrade EKS cluster version?

```bash
# 1. Check current version
kubectl version --short

# 2. Read upgrade notes
# https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html

# 3. Test in dev first
atmos terraform plan eks -s mycompany-dev-use1 \
  -var='default_kubernetes_version=1.29'

atmos terraform apply eks -s mycompany-dev-use1 \
  -var='default_kubernetes_version=1.29'

# 4. Wait for control plane upgrade (15-20 min)
aws eks wait cluster-active --name dev-use1-primary

# 5. Upgrade node groups
aws eks update-nodegroup-version \
  --cluster-name dev-use1-primary \
  --nodegroup-name system \
  --kubernetes-version 1.29

# 6. Upgrade add-ons
atmos terraform apply eks-addons -s mycompany-dev-use1

# 7. Test thoroughly before production
./scripts/smoke-test.sh

# 8. Repeat for staging and production
```

### Where are the logs?

**Application Logs:**
```bash
# Kubernetes pods
kubectl logs -f <pod-name>
kubectl logs -l app=myapp --tail=100

# CloudWatch Logs
aws logs tail /aws/eks/<cluster-name>/cluster --follow
```

**Infrastructure Logs:**
```bash
# Terraform state changes
aws s3 ls s3://terraform-state-${AWS_ACCOUNT_ID}/

# CloudTrail (API calls)
aws cloudtrail lookup-events --max-results 50

# VPC Flow Logs
aws logs tail /aws/vpc/flowlogs --follow
```

**Audit Logs:**
```bash
# EKS audit logs
aws logs tail /aws/eks/<cluster-name>/cluster --follow \
  --filter-pattern '{ $.verb = "delete" || $.verb = "create" }'

# RDS events
aws rds describe-events --source-type db-instance --duration 1440
```

### How do I access monitoring dashboards?

**CloudWatch:**
```bash
# List dashboards
aws cloudwatch list-dashboards

# Open in browser
open "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:"
```

**Kubernetes Metrics:**
```bash
# Install metrics server (if not present)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# View metrics
kubectl top nodes
kubectl top pods --all-namespaces
```

**Prometheus/Grafana (if installed):**
```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open in browser
open http://localhost:3000
```

---

## Troubleshooting

### Why is my Terraform state locked?

```bash
# Check lock status
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "<component>/terraform.tfstate"}}'

# If lock is stale, force unlock
terraform force-unlock <lock-id>

# Verify unlock
atmos terraform state list <component> -s <stack>
```

### Why can't kubectl connect to my cluster?

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig \
  --name <cluster-name> \
  --region <region>

# 2. Verify AWS credentials
aws sts get-caller-identity

# 3. Check cluster status
aws eks describe-cluster --name <cluster-name>

# 4. Test connection
kubectl cluster-info

# 5. Check aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml
```

### Why is my deployment stuck?

```bash
# Check pod status
kubectl get pods -l app=myapp

# Describe pod for events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Common issues:
# 1. Image pull errors -> Check ECR permissions
kubectl get events --field-selector involvedObject.name=<pod-name>

# 2. Resource limits -> Check node capacity
kubectl describe nodes

# 3. Pending PVCs -> Check storage classes
kubectl get pvc
```

### How do I fix "insufficient subnet capacity"?

```bash
# 1. Check current subnet allocation
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[*].[SubnetId,AvailableIpAddressCount,CidrBlock]'

# 2. Options:
# a) Add more subnets
vim stacks/orgs/mycompany/prod/us-east-1/use1/vpc.yaml
# Add: private_subnets_cidr: ["10.x.30.0/24", "10.x.31.0/24"]

# b) Use larger CIDR blocks (requires recreation)
# Change: vpc_cidr: 10.x.0.0/16 to 10.x.0.0/15

# 3. Apply changes
atmos terraform apply vpc -s mycompany-prod-use1
```

---

## Cost & Billing

### How much does this cost?

Estimated monthly costs by environment:

| Environment | Compute | Database | Storage | Network | Total |
|------------|---------|----------|---------|---------|-------|
| **Development** | $300 | $100 | $50 | $45 | **$495** |
| **Staging** | $800 | $200 | $150 | $45 | **$1,195** |
| **Production** | $4,000 | $1,500 | $500 | $135 | **$6,135** |

See [COST_ESTIMATION.md](./COST_ESTIMATION.md) for detailed breakdown.

### How can I reduce costs?

**Quick wins:**
```bash
# 1. Use Spot instances (70% savings)
# Update eks.yaml:
node_groups:
  spot:
    capacity_type: "SPOT"
    instance_types: ["t3.large", "t3a.large", "m5.large"]

# 2. Auto-shutdown dev environments
./scripts/schedule-shutdown.sh --environment dev --weekends true

# 3. Use gp3 instead of gp2 volumes (20% savings)
# All new volumes use gp3 by default

# 4. Enable S3 Intelligent Tiering
aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket my-bucket \
  --id intelligent-tiering \
  --intelligent-tiering-configuration file://tiering-config.json

# 5. Right-size resources
./scripts/find-underutilized-resources.sh
```

See [Cost Optimization](#../architecture/CLOUD_ARCHITECTURE_OPTIMIZATION_PLAN.md) for comprehensive strategies.

### How do I track costs by environment/team?

```bash
# Enable cost allocation tags
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status \
  Key=Environment,Status=Active \
  Key=Team,Status=Active \
  Key=CostCenter,Status=Active

# Generate cost report by tag
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Environment

# Create budget alerts
aws budgets create-budget \
  --account-id ${AWS_ACCOUNT_ID} \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

### How do I estimate costs for a new environment?

Use the AWS Pricing Calculator:

```bash
# 1. List required resources
atmos describe component <component> -s <stack>

# 2. Use pricing calculator
open "https://calculator.aws/"

# 3. Or use CLI for estimates
aws pricing get-products \
  --service-code AmazonEKS \
  --filters Type=TERM_MATCH,Field=location,Value=US East (N. Virginia) \
  --format-version aws_v1

# 4. Generate custom estimate
./scripts/cost-estimate.sh --environment new-prod --region us-west-2
```

---

## Security

### How do I rotate credentials?

**RDS Password:**
```bash
# Use rotation script
./scripts/rotate-rds-password.sh --database my-database

# Or manually:
NEW_PASS=$(openssl rand -base64 32)
aws secretsmanager update-secret \
  --secret-id /prod/database/master-password \
  --secret-string "${NEW_PASS}"

aws rds modify-db-instance \
  --db-instance-identifier my-database \
  --master-user-password "${NEW_PASS}"

kubectl rollout restart deployment/myapp
```

**API Keys:**
```bash
# Rotate in Secrets Manager
aws secretsmanager rotate-secret \
  --secret-id /prod/api-keys

# Update application
kubectl create secret generic api-keys \
  --from-literal=key=$(aws secretsmanager get-secret-value --secret-id /prod/api-keys --query SecretString --output text) \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/myapp
```

**SSL Certificates:**
```bash
# Use Atmos workflow
atmos workflow rotate-certificate \
  tenant=mycompany \
  account=prod \
  environment=use1 \
  certificate_name=*.example.com
```

### How do I audit security?

```bash
# Run security audit script
./scripts/security-audit.sh

# Check AWS Config compliance
aws configservice describe-compliance-by-config-rule

# Review GuardDuty findings
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

# Check for security groups allowing 0.0.0.0/0
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0"

# Review IAM policies
./scripts/check-iam-permissions.sh --audit
```

### How do I enable MFA?

```bash
# Enable MFA for IAM users
aws iam enable-mfa-device \
  --user-name myuser \
  --serial-number arn:aws:iam::${AWS_ACCOUNT_ID}:mfa/myuser \
  --authentication-code-1 123456 \
  --authentication-code-2 789012

# Require MFA for sensitive operations
# Update IAM policy to include:
{
  "Condition": {
    "Bool": {
      "aws:MultiFactorAuthPresent": "true"
    }
  }
}
```

### What are the security best practices?

1. **Network Security:**
   - Use private subnets for workloads
   - Implement security groups with least privilege
   - Enable VPC Flow Logs
   - Use VPC endpoints to avoid internet traffic

2. **Data Security:**
   - Enable encryption at rest (KMS)
   - Use TLS 1.3 for data in transit
   - Rotate credentials regularly
   - Store secrets in Secrets Manager

3. **Access Control:**
   - Implement IAM least privilege
   - Use IAM roles instead of access keys
   - Enable MFA for privileged users
   - Regular access reviews

4. **Monitoring:**
   - Enable CloudTrail for audit logs
   - Configure GuardDuty for threat detection
   - Set up AWS Config for compliance
   - Monitor with CloudWatch alarms

See [Security Best Practices Guide](./architecture/security-best-practices-guide.md) for details.

---

## Scaling

### When should I scale horizontally vs vertically?

**Horizontal Scaling (add more instances):**
- Use for: Stateless applications, microservices
- Benefits: Better fault tolerance, gradual scaling
- Example: Add more EKS nodes, scale pod replicas

**Vertical Scaling (bigger instances):**
- Use for: Databases, stateful applications, memory-intensive workloads
- Benefits: Simpler, no code changes needed
- Drawbacks: Requires downtime, single point of failure

**Recommendation:**
```yaml
# Application tier: Horizontal
node_groups:
  application:
    instance_types: ["c5.xlarge"]
    min_size: 3
    max_size: 20

# Database tier: Vertical + read replicas
rds:
  instance_class: db.r5.2xlarge
  read_replicas: 2  # Horizontal for reads
```

### How do I implement auto-scaling?

**Kubernetes HPA:**
```bash
# CPU-based
kubectl autoscale deployment myapp \
  --min=3 --max=20 --cpu-percent=70

# Memory-based (requires metrics-server)
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF
```

**KEDA (event-driven):**
```bash
# Install KEDA
helm install keda kedacore/keda --namespace keda --create-namespace

# Scale based on queue length
kubectl apply -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: myapp-scaler
spec:
  scaleTargetRef:
    name: myapp
  minReplicaCount: 2
  maxReplicaCount: 20
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/123456789012/myqueue
      queueLength: "5"
      awsRegion: "us-east-1"
EOF
```

**Node Auto-Scaling (Karpenter):**
```bash
# Deploy Karpenter
atmos terraform apply eks-addons -s mycompany-prod-use1

# Configure provisioner
kubectl apply -f - <<EOF
apiVersion: karpenter.sh/v1alpha5
kind:Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["c5.large", "c5.xlarge", "m5.large"]
  limits:
    resources:
      cpu: 1000
  ttlSecondsAfterEmpty: 30
EOF
```

---

## Disaster Recovery

### What's the RTO/RPO?

| Scenario | RTO (Recovery Time) | RPO (Data Loss) |
|----------|-------------------|-----------------|
| Pod failure | < 1 minute | None |
| Node failure | < 5 minutes | None |
| AZ failure | < 10 minutes | < 1 minute |
| Region failure | < 1 hour | < 5 minutes |
| Data corruption | < 4 hours | Up to backup interval |

### How do I test disaster recovery?

```bash
# 1. Create test environment
./scripts/create-dr-test-environment.sh

# 2. Test RDS failover
aws rds failover-db-cluster --db-cluster-identifier my-cluster

# 3. Test node failure
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 4. Test application failure
kubectl delete pod -l app=myapp

# 5. Test backup restore
velero restore create test-restore --from-backup latest

# 6. Verify recovery
./scripts/verify-dr-recovery.sh

# 7. Document results
vim docs/operations/dr-test-$(date +%Y%m%d).md
```

### How do I failover to DR region?

```bash
# 1. Promote RDS read replica in DR region
aws rds promote-read-replica \
  --db-instance-identifier dr-database \
  --region us-west-2

# 2. Scale up DR EKS cluster
aws eks update-nodegroup-config \
  --cluster-name dr-cluster \
  --nodegroup-name application \
  --scaling-config minSize=10,maxSize=30,desiredSize=20 \
  --region us-west-2

# 3. Update DNS to point to DR
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dr-dns-update.json

# 4. Deploy application to DR
kubectl config use-context dr-cluster
kubectl apply -f manifests/

# 5. Verify DR environment
./scripts/smoke-test.sh --region us-west-2

# 6. Monitor and adjust
kubectl get pods --all-namespaces
aws cloudwatch get-metric-statistics ...
```

---

## Additional Resources

- [Deployment Guide](./DEPLOYMENT_GUIDE.md) - Complete deployment instructions
- [Operations Guide](./OPERATIONS_GUIDE.md) - Daily operations procedures
- [Architecture Documentation](./architecture/) - System design and diagrams
- [Component READMEs](../components/terraform/) - Detailed component documentation
- [Troubleshooting Guide](./operations/TROUBLESHOOTING.md) - Common issues and solutions

---

**Still have questions?**
- File an issue in the repository
- Contact: platform-team@example.com
- Slack: #infrastructure-support

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
