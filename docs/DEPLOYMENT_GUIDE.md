# Complete Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [AWS Account Setup](#aws-account-setup)
3. [Backend Initialization](#backend-initialization)
4. [VPC Deployment](#vpc-deployment)
5. [Security Baseline](#security-baseline)
6. [EKS Cluster Deployment](#eks-cluster-deployment)
7. [Application Components](#application-components)
8. [Validation & Testing](#validation--testing)
9. [Post-Deployment Tasks](#post-deployment-tasks)
10. [Rollback Procedures](#rollback-procedures)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| Terraform | 1.11.0+ | `brew install terraform` |
| Atmos CLI | 1.163.0+ | `brew install cloudposse/tap/atmos` |
| AWS CLI | 2.0+ | `brew install awscli` |
| Python | 3.11+ | `brew install python@3.11` |
| kubectl | 1.28+ | `brew install kubectl` |
| Helm | 3.12+ | `brew install helm` |

### Verify Installation

```bash
# Check all tool versions
terraform version
atmos version
aws --version
python3 --version
kubectl version --client
helm version
```

### Prerequisites Checklist

- [ ] AWS account with administrator access
- [ ] AWS CLI configured with credentials
- [ ] S3 bucket for Terraform state (or ability to create one)
- [ ] DynamoDB table for state locking (or ability to create one)
- [ ] Domain name registered in Route 53 (optional, for DNS)
- [ ] ACM certificate for your domain (optional, for HTTPS)

---

## AWS Account Setup

### 1. Configure AWS CLI

```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

### 2. Set Environment Variables

Create a `.env` file in the project root:

```bash
# AWS Configuration
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Terraform State Backend
export TF_STATE_BUCKET=terraform-state-${AWS_ACCOUNT_ID}
export TF_STATE_DYNAMODB_TABLE=terraform-state-lock
export TF_STATE_REGION=us-east-1

# Project Configuration
export TENANT=mycompany
export ACCOUNT=dev
export ENVIRONMENT=use1
export VPC_CIDR=10.0.0.0/16

# Load environment
source .env
```

### 3. Verify IAM Permissions

Your AWS user/role needs these permissions:

```bash
# Check IAM permissions
./scripts/check-iam-permissions.sh

# Required permissions:
# - EC2: Full access for VPC, subnets, security groups
# - EKS: Full access for cluster management
# - IAM: Create roles and policies
# - S3: Create and manage buckets
# - DynamoDB: Create and manage tables
# - CloudWatch: Create log groups and metrics
# - KMS: Create and manage keys
```

---

## Backend Initialization

### 1. Bootstrap Backend Infrastructure

The backend stores Terraform state and provides state locking.

```bash
# Initialize backend (S3 bucket + DynamoDB table)
atmos workflow bootstrap-backend -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

This creates:
- S3 bucket: `terraform-state-${AWS_ACCOUNT_ID}` with versioning and encryption
- DynamoDB table: `terraform-state-lock` with LockID key
- KMS key for state encryption
- Bucket policies and lifecycle rules

### 2. Verify Backend

```bash
# Check S3 bucket
aws s3 ls s3://${TF_STATE_BUCKET}/

# Check DynamoDB table
aws dynamodb describe-table --table-name ${TF_STATE_DYNAMODB_TABLE}

# Validate backend configuration
atmos terraform validate backend -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### 3. Backend Configuration

The backend is configured in `stacks/catalog/backend/defaults.yaml`:

```yaml
backend_type: s3
backend:
  s3:
    encrypt: true
    bucket: terraform-state-${AWS_ACCOUNT_ID}
    key: terraform.tfstate
    dynamodb_table: terraform-state-lock
    region: us-east-1
```

---

## VPC Deployment

### 1. Plan VPC Deployment

```bash
# Review VPC configuration
cat stacks/catalog/vpc/defaults.yaml

# Plan VPC changes
atmos terraform plan vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### 2. Deploy VPC

```bash
# Deploy VPC and networking
atmos terraform apply vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Deployment creates:
# - VPC with specified CIDR block
# - 3 public subnets (one per AZ)
# - 3 private subnets (one per AZ)
# - 3 database subnets (one per AZ)
# - Internet Gateway
# - NAT Gateways (1 or 3 depending on environment)
# - Route tables
# - VPC Flow Logs
```

### 3. Verify VPC

```bash
# Get VPC outputs
atmos terraform output vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Verify VPC resources
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=${ENVIRONMENT}"
aws ec2 describe-subnets --filters "Name=tag:Environment,Values=${ENVIRONMENT}"

# Test connectivity
aws ec2 describe-nat-gateways --filter "Name=tag:Environment,Values=${ENVIRONMENT}"
```

### 4. VPC Configuration Examples

**Development Environment:**
```yaml
vars:
  vpc_cidr: 10.0.0.0/16
  public_subnets_cidr:
    - 10.0.1.0/24
    - 10.0.2.0/24
    - 10.0.3.0/24
  private_subnets_cidr:
    - 10.0.10.0/24
    - 10.0.11.0/24
    - 10.0.12.0/24
  nat_gateway_count: 1  # Cost optimization
  enable_flow_logs: true
```

**Production Environment:**
```yaml
vars:
  vpc_cidr: 10.2.0.0/16
  public_subnets_cidr:
    - 10.2.1.0/24
    - 10.2.2.0/24
    - 10.2.3.0/24
  private_subnets_cidr:
    - 10.2.10.0/24
    - 10.2.11.0/24
    - 10.2.12.0/24
  nat_gateway_count: 3  # High availability
  enable_flow_logs: true
```

---

## Security Baseline

### 1. Deploy IAM Roles

```bash
# Plan IAM resources
atmos terraform plan iam -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Deploy IAM roles and policies
atmos terraform apply iam -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### 2. Deploy Security Groups

```bash
# Plan security groups
atmos terraform plan securitygroup -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Deploy security groups
atmos terraform apply securitygroup -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Created security groups:
# - eks-cluster-sg: EKS cluster security group
# - eks-node-sg: EKS worker nodes
# - rds-sg: RDS database instances
# - alb-sg: Application Load Balancer
# - bastion-sg: Bastion hosts (if enabled)
```

### 3. Configure Secrets Manager

```bash
# Deploy secrets manager
atmos terraform apply secretsmanager -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Store initial secrets
aws secretsmanager create-secret \
  --name /${ENVIRONMENT}/database/master-password \
  --secret-string "$(openssl rand -base64 32)"

aws secretsmanager create-secret \
  --name /${ENVIRONMENT}/app/api-keys \
  --secret-string '{}'
```

### 4. Enable AWS Config & GuardDuty

```bash
# Enable AWS Config for compliance
aws configservice put-configuration-recorder \
  --configuration-recorder name=default,roleARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/config-role \
  --recording-group allSupported=true,includeGlobalResourceTypes=true

# Enable GuardDuty for threat detection
aws guardduty create-detector --enable
```

---

## EKS Cluster Deployment

### 1. Plan EKS Deployment

```bash
# Review EKS configuration
cat stacks/orgs/${TENANT}/${ACCOUNT}/${REGION}/${ENVIRONMENT}/eks.yaml

# Plan EKS cluster
atmos terraform plan eks -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### 2. Deploy EKS Cluster

```bash
# Deploy EKS cluster (takes 15-20 minutes)
atmos terraform apply eks -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Monitor deployment progress
watch -n 10 aws eks describe-cluster \
  --name ${ENVIRONMENT}-primary \
  --query 'cluster.status'
```

### 3. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name ${ENVIRONMENT}-primary \
  --region ${AWS_REGION}

# Verify connection
kubectl cluster-info
kubectl get nodes

# Expected output:
# NAME                           STATUS   ROLES    AGE   VERSION
# ip-10-0-10-123.ec2.internal   Ready    <none>   5m    v1.28.0-eks-abcd123
# ip-10-0-11-234.ec2.internal   Ready    <none>   5m    v1.28.0-eks-abcd123
```

### 4. Deploy EKS Add-ons

```bash
# Plan add-ons
atmos terraform plan eks-addons -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Deploy add-ons (ALB controller, Karpenter, monitoring)
atmos terraform apply eks-addons -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Verify add-ons
kubectl get pods -n kube-system
kubectl get pods -n karpenter
kubectl get pods -n aws-load-balancer-controller
```

### 5. Verify EKS Setup

```bash
# Check cluster health
kubectl get --raw='/readyz?verbose'

# Verify node groups
aws eks list-nodegroups --cluster-name ${ENVIRONMENT}-primary

# Check OIDC provider
aws eks describe-cluster \
  --name ${ENVIRONMENT}-primary \
  --query 'cluster.identity.oidc.issuer'
```

---

## Application Components

### 1. Deploy RDS Database

```bash
# Plan RDS deployment
atmos terraform plan rds -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Deploy RDS (takes 10-15 minutes)
atmos terraform apply rds -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Get database endpoint
atmos terraform output rds -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT} | \
  jq -r '.db_endpoint.value'
```

### 2. Deploy API Gateway

```bash
# Deploy API Gateway
atmos terraform apply apigateway -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Get API Gateway URL
atmos terraform output apigateway -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### 3. Deploy Lambda Functions

```bash
# Deploy Lambda functions
atmos terraform apply lambda -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Test Lambda function
aws lambda invoke \
  --function-name ${ENVIRONMENT}-health-check \
  --region ${AWS_REGION} \
  /tmp/response.json
```

### 4. Configure DNS

```bash
# Deploy DNS records
atmos terraform apply dns -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Verify DNS records
dig +short ${ENVIRONMENT}.yourdomain.com
```

---

## Validation & Testing

### 1. Run Complete Validation

```bash
# Validate all components
atmos workflow validate tenant=${TENANT} account=${ACCOUNT} environment=${ENVIRONMENT}

# Expected output: All validations pass
```

### 2. Test Network Connectivity

```bash
# Test from EKS pod to RDS
kubectl run test-pod --image=mysql:8.0 -it --rm -- \
  mysql -h <rds-endpoint> -u admin -p

# Test internet connectivity from private subnet
kubectl run test-pod --image=curlimages/curl -it --rm -- \
  curl -I https://www.google.com
```

### 3. Test Application Health

```bash
# Deploy test application
kubectl apply -f examples/test-app.yaml

# Check deployment
kubectl get deployments
kubectl get services

# Test application endpoint
curl https://${ENVIRONMENT}.yourdomain.com/health
```

### 4. Verify Monitoring

```bash
# Check CloudWatch dashboards
aws cloudwatch list-dashboards

# View EKS cluster metrics
kubectl top nodes
kubectl top pods --all-namespaces

# Check Prometheus metrics (if installed)
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
```

---

## Post-Deployment Tasks

### 1. Configure Backups

```bash
# Enable automated backups for RDS
aws rds modify-db-instance \
  --db-instance-identifier ${ENVIRONMENT}-primary \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00"

# Configure Velero for EKS backups
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=${VELERO_BUCKET} \
  --set configuration.backupStorageLocation.config.region=${AWS_REGION}
```

### 2. Set Up Monitoring Alerts

```bash
# Deploy monitoring stack
atmos terraform apply monitoring -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Configure CloudWatch alarms
aws cloudwatch put-metric-alarm \
  --alarm-name ${ENVIRONMENT}-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

### 3. Configure Cost Monitoring

```bash
# Create budget alerts
aws budgets create-budget \
  --account-id ${AWS_ACCOUNT_ID} \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json

# Enable Cost Explorer
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost
```

### 4. Document Configuration

```bash
# Export all outputs to documentation
./scripts/export-outputs.sh > docs/deployment-outputs.md

# Generate architecture diagrams
atmos describe stacks --format=json | \
  python3 scripts/generate-diagram.py > docs/current-architecture.md
```

### 5. Team Access

```bash
# Add team members to AWS account
aws iam create-user --user-name developer1
aws iam attach-user-policy \
  --user-name developer1 \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

# Configure kubectl access
kubectl create clusterrolebinding developer1-admin \
  --clusterrole=cluster-admin \
  --user=developer1
```

---

## Rollback Procedures

### Emergency Rollback Checklist

- [ ] Identify failed component
- [ ] Check Terraform state
- [ ] Review CloudWatch logs
- [ ] Backup current state
- [ ] Execute rollback
- [ ] Verify rollback success
- [ ] Document incident

### Rollback VPC Changes

```bash
# CAUTION: This will destroy VPC resources
# Ensure no dependencies exist

# Destroy VPC
atmos terraform destroy vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Redeploy previous version
git checkout <previous-commit>
atmos terraform apply vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### Rollback EKS Changes

```bash
# Scale down node groups first
aws eks update-nodegroup-config \
  --cluster-name ${ENVIRONMENT}-primary \
  --nodegroup-name system \
  --scaling-config minSize=0,maxSize=0,desiredSize=0

# Rollback EKS
atmos terraform destroy eks -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

# Redeploy from previous state
git checkout <previous-commit>
atmos terraform apply eks -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}
```

### Rollback Application Changes

```bash
# Kubernetes rollback
kubectl rollout undo deployment/<deployment-name>

# Verify rollback
kubectl rollout status deployment/<deployment-name>
```

### Restore from Terraform State

```bash
# List state versions
aws s3api list-object-versions \
  --bucket ${TF_STATE_BUCKET} \
  --prefix ${COMPONENT}/terraform.tfstate

# Restore previous state version
aws s3api get-object \
  --bucket ${TF_STATE_BUCKET} \
  --key ${COMPONENT}/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.backup

# Copy back
aws s3 cp terraform.tfstate.backup \
  s3://${TF_STATE_BUCKET}/${COMPONENT}/terraform.tfstate
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Backend Initialization Fails

```bash
# Error: Failed to create S3 bucket
# Solution: Check IAM permissions
aws iam get-user-policy --user-name $(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2) --policy-name S3FullAccess

# Solution: Manually create bucket
aws s3 mb s3://${TF_STATE_BUCKET} --region ${AWS_REGION}
aws s3api put-bucket-versioning \
  --bucket ${TF_STATE_BUCKET} \
  --versioning-configuration Status=Enabled
```

#### Issue 2: VPC Deployment Fails

```bash
# Error: Insufficient subnet space
# Solution: Adjust CIDR blocks in configuration

# Check available CIDR space
aws ec2 describe-vpcs --filters "Name=cidr,Values=10.0.0.0/16"

# Solution: Use different CIDR range
export VPC_CIDR=10.1.0.0/16
```

#### Issue 3: EKS Cluster Creation Fails

```bash
# Error: Cluster creation failed
# Check cluster status
aws eks describe-cluster --name ${ENVIRONMENT}-primary

# Common solutions:
# 1. Ensure subnets span 2+ AZs
aws ec2 describe-subnets --subnet-ids <subnet-ids> \
  --query 'Subnets[*].AvailabilityZone'

# 2. Check security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# 3. Verify IAM role trust relationship
aws iam get-role --role-name ${ENVIRONMENT}-eks-cluster-role
```

#### Issue 4: kubectl Cannot Connect

```bash
# Error: Unable to connect to the server
# Solution: Update kubeconfig
aws eks update-kubeconfig \
  --name ${ENVIRONMENT}-primary \
  --region ${AWS_REGION} \
  --alias ${ENVIRONMENT}

# Verify AWS credentials
aws sts get-caller-identity

# Check cluster endpoint
aws eks describe-cluster \
  --name ${ENVIRONMENT}-primary \
  --query 'cluster.endpoint'
```

#### Issue 5: Terraform State Lock

```bash
# Error: State locked
# Check lock status
aws dynamodb get-item \
  --table-name ${TF_STATE_DYNAMODB_TABLE} \
  --key '{"LockID": {"S": "${COMPONENT}/terraform.tfstate"}}'

# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Getting Help

1. Check logs:
   ```bash
   # Terraform logs
   export TF_LOG=DEBUG
   atmos terraform plan vpc -s ${TENANT}-${ACCOUNT}-${ENVIRONMENT}

   # CloudWatch logs
   aws logs tail /aws/eks/${ENVIRONMENT}-primary/cluster --follow
   ```

2. Review documentation:
   - Component README: `/components/terraform/<component>/README.md`
   - Architecture docs: `/docs/architecture/`
   - Operations guide: `/docs/OPERATIONS_GUIDE.md`

3. Contact support:
   - File an issue in the repository
   - Check FAQ: `/docs/FAQ.md`
   - Review troubleshooting: `/docs/operations/TROUBLESHOOTING.md`

---

## Next Steps

After successful deployment:

1. Review the [Operations Guide](./OPERATIONS_GUIDE.md) for day-to-day management
2. Set up CI/CD pipelines (see [CI/CD Integration Guide](./workflows/cicd-integration-guide.md))
3. Configure monitoring dashboards (see [Monitoring Guide](./components/monitoring-guide.md))
4. Implement disaster recovery procedures (see [DR Guide](./operations/disaster-recovery-guide.md))
5. Schedule regular security audits

---

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
**Review Cycle**: Monthly
