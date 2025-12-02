# Quick Deployment Guide

Fast-track deployment guides for the Alexandria Library stack templates. Each guide provides step-by-step instructions to deploy production-ready infrastructure in minutes.

---

## Table of Contents

1. [Web Application (15 minutes)](#deploy-web-application-in-15-minutes)
2. [Microservices Platform (30 minutes)](#deploy-microservices-platform-in-30-minutes)
3. [Data Pipeline (20 minutes)](#deploy-data-pipeline-in-20-minutes)
4. [Serverless API (10 minutes)](#deploy-serverless-api-in-10-minutes)
5. [Batch Processing (25 minutes)](#deploy-batch-processing-in-25-minutes)

---

## Prerequisites Checklist

Before starting any deployment, ensure you have:

### Required Tools

| Tool | Version | Verify Command | Installation |
|------|---------|----------------|--------------|
| AWS CLI | 2.0+ | `aws --version` | `brew install awscli` |
| Terraform | 1.5+ | `terraform version` | `brew install terraform` |
| Atmos | 1.38+ | `atmos version` | `brew install cloudposse/tap/atmos` |
| jq | 1.6+ | `jq --version` | `brew install jq` |

### AWS Configuration

```bash
# Configure AWS credentials
aws configure

# Verify credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/yourname"
# }
```

### Environment Variables

```bash
# Set required environment variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Optional: Set default tenant/account
export TENANT=mycompany
export ACCOUNT=dev
```

### Quick Verification Script

```bash
# Run this to verify all prerequisites
./scripts/install-dependencies.sh --check
```

---

## Deploy Web Application in 15 Minutes

Deploy a complete web application infrastructure with VPC, RDS database, and monitoring.

### Architecture Overview

```
                    +------------------+
                    |   Route 53       |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   CloudFront     |
                    +--------+---------+
                             |
            +----------------+----------------+
            |                                 |
    +-------v-------+               +---------v--------+
    |  Public ALB   |               |  Static Assets   |
    +-------+-------+               |      (S3)        |
            |                       +------------------+
    +-------v-------+
    | Private Subnet|
    | +----------+  |
    | |  EC2/ECS |  |
    | +----+-----+  |
    |      |        |
    | +----v-----+  |
    | |   RDS    |  |
    | +----------+  |
    +---------------+
```

### Components Deployed

| Component | Resources | Estimated Time |
|-----------|-----------|----------------|
| VPC | VPC, Subnets, NAT Gateway, Route Tables | 5 min |
| Security Groups | Web, App, Database SGs | 2 min |
| IAM | Roles, Policies | 3 min |
| RDS | MySQL/PostgreSQL Database | 8 min |
| Monitoring | CloudWatch Dashboards, Alarms | 2 min |

### Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$150 |
| Staging | ~$300 |
| Production | ~$800 |

### Step-by-Step Deployment

#### Step 1: Create Environment (2 minutes)

```bash
# Create new environment
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment webapp-01 \
  --region us-east-1 \
  --template web-application \
  --env-type development

# Expected output:
# ==> Creating Directory Structure
# [SUCCESS] Created directory: stacks/orgs/mycompany/dev/webapp-01
# ==> Generating Main Stack Configuration
# [SUCCESS] Created: stacks/orgs/mycompany/dev/webapp-01/main.yaml
# ...
```

#### Step 2: Review Configuration (1 minute)

```bash
# Review generated configuration
cat stacks/orgs/mycompany/dev/webapp-01/main.yaml

# Customize if needed
vim stacks/orgs/mycompany/dev/webapp-01/vars.yaml
```

#### Step 3: Validate Stack (1 minute)

```bash
# Validate configuration
atmos validate stacks

# Expected output:
# Validating stack configurations...
# All stacks validated successfully
```

#### Step 4: Deploy Infrastructure (10 minutes)

```bash
# Option A: Use deploy script (recommended)
./scripts/deploy-stack.sh \
  --template web-application \
  --stack mycompany-dev-webapp-01 \
  --auto-approve

# Option B: Use Atmos workflow
atmos workflow deploy-template -f deploy-template.yaml \
  template=web-application \
  tenant=mycompany \
  account=dev \
  environment=webapp-01 \
  auto_approve=true

# Option C: Deploy manually step by step
atmos terraform apply vpc -s mycompany-dev-webapp-01 -auto-approve
atmos terraform apply securitygroup -s mycompany-dev-webapp-01 -auto-approve
atmos terraform apply iam -s mycompany-dev-webapp-01 -auto-approve
atmos terraform apply rds -s mycompany-dev-webapp-01 -auto-approve
atmos terraform apply monitoring -s mycompany-dev-webapp-01 -auto-approve
```

#### Step 5: Verify Deployment (1 minute)

```bash
# Check VPC outputs
atmos terraform output vpc -s mycompany-dev-webapp-01

# Expected outputs:
# vpc_id = "vpc-0123456789abcdef0"
# public_subnet_ids = ["subnet-abc...", "subnet-def..."]
# private_subnet_ids = ["subnet-123...", "subnet-456..."]

# Check RDS outputs
atmos terraform output rds -s mycompany-dev-webapp-01

# Expected outputs:
# endpoint = "mycompany-dev-webapp-01-db.xxx.us-east-1.rds.amazonaws.com"
# port = 3306

# Verify in AWS Console
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'
```

### Verification Checklist

- [ ] VPC created with public and private subnets
- [ ] NAT Gateway operational
- [ ] Security groups configured
- [ ] RDS instance running and accessible
- [ ] CloudWatch dashboards available
- [ ] Cost allocation tags applied

### Next Steps

1. **Deploy your application**
   ```bash
   # Configure database connection
   export DB_HOST=$(atmos terraform output rds -s mycompany-dev-webapp-01 | grep endpoint | cut -d'"' -f2)
   ```

2. **Set up CI/CD pipeline**
3. **Configure custom domain**
4. **Enable backups**

---

## Deploy Microservices Platform in 30 Minutes

Deploy a production-ready Kubernetes platform with EKS, monitoring, and service mesh support.

### Architecture Overview

```
                    +-------------------+
                    |   Route 53        |
                    +--------+----------+
                             |
                    +--------v----------+
                    |   ALB Ingress     |
                    +--------+----------+
                             |
    +--------------------------------------------+
    |                    EKS Cluster              |
    |  +----------+  +----------+  +----------+  |
    |  | Service  |  | Service  |  | Service  |  |
    |  |    A     |  |    B     |  |    C     |  |
    |  +----+-----+  +----+-----+  +----+-----+  |
    |       |             |             |        |
    |  +----v-------------v-------------v----+   |
    |  |        Service Mesh (optional)      |   |
    |  +-------------------------------------+   |
    +--------------------------------------------+
                             |
    +------------------------+------------------------+
    |                        |                        |
    +--------v------+  +-----v--------+  +------------v---+
    |     RDS       |  |   ElastiCache |  | Secrets Manager |
    +---------------+  +--------------+  +----------------+
```

### Components Deployed

| Component | Resources | Estimated Time |
|-----------|-----------|----------------|
| VPC | VPC, Subnets, NAT Gateway | 5 min |
| Security Groups | EKS, Node, Service SGs | 2 min |
| IAM | EKS Roles, Node Roles, IRSA | 3 min |
| EKS | Control Plane, Node Groups | 15 min |
| EKS Add-ons | ALB Controller, Autoscaler | 8 min |
| Monitoring | CloudWatch, Container Insights | 3 min |
| Secrets | Secrets Manager, External Secrets | 2 min |

### Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$300 |
| Staging | ~$600 |
| Production | ~$2,500 |

### Step-by-Step Deployment

#### Step 1: Create Environment (2 minutes)

```bash
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment k8s-01 \
  --region us-east-1 \
  --template microservices-platform \
  --env-type development
```

#### Step 2: Configure EKS Settings (2 minutes)

```bash
# Edit vars.yaml to customize EKS
cat >> stacks/orgs/mycompany/dev/k8s-01/vars.yaml << 'EOF'

# EKS Configuration
vars:
  eks:
    cluster_version: "1.28"
    node_groups:
      general:
        instance_types: ["t3.medium"]
        min_size: 2
        max_size: 5
        desired_size: 3
      spot:
        instance_types: ["t3.large", "t3.xlarge"]
        capacity_type: "SPOT"
        min_size: 0
        max_size: 10
        desired_size: 2
EOF
```

#### Step 3: Validate Configuration (1 minute)

```bash
atmos validate stacks
atmos terraform validate eks -s mycompany-dev-k8s-01
```

#### Step 4: Deploy Infrastructure (25 minutes)

```bash
# Full deployment
./scripts/deploy-stack.sh \
  --template microservices-platform \
  --stack mycompany-dev-k8s-01 \
  --auto-approve

# Or step by step with progress
atmos terraform apply vpc -s mycompany-dev-k8s-01 -auto-approve
echo "[1/7] VPC deployed"

atmos terraform apply securitygroup -s mycompany-dev-k8s-01 -auto-approve
echo "[2/7] Security groups deployed"

atmos terraform apply iam -s mycompany-dev-k8s-01 -auto-approve
echo "[3/7] IAM roles deployed"

atmos terraform apply eks -s mycompany-dev-k8s-01 -auto-approve
echo "[4/7] EKS cluster deployed (this takes ~15 minutes)"

atmos terraform apply eks-addons -s mycompany-dev-k8s-01 -auto-approve
echo "[5/7] EKS add-ons deployed"

atmos terraform apply monitoring -s mycompany-dev-k8s-01 -auto-approve
echo "[6/7] Monitoring deployed"

atmos terraform apply secretsmanager -s mycompany-dev-k8s-01 -auto-approve
echo "[7/7] Secrets manager deployed"
```

#### Step 5: Configure kubectl (1 minute)

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name mycompany-dev-k8s-01-eks \
  --region us-east-1

# Verify connection
kubectl get nodes

# Expected output:
# NAME                                        STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.us-east-1.compute.internal    Ready    <none>   5m    v1.28.x
# ip-10-0-2-456.us-east-1.compute.internal    Ready    <none>   5m    v1.28.x
```

#### Step 6: Verify Deployment (2 minutes)

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check add-ons
kubectl get pods -n kube-system
kubectl get pods -n aws-load-balancer-controller

# View EKS outputs
atmos terraform output eks -s mycompany-dev-k8s-01
```

### Verification Checklist

- [ ] EKS cluster running and accessible
- [ ] Node groups healthy with expected capacity
- [ ] AWS Load Balancer Controller installed
- [ ] Cluster Autoscaler configured
- [ ] External DNS operational
- [ ] Container Insights enabled
- [ ] kubectl configured and working

### Next Steps

1. **Deploy sample application**
   ```bash
   kubectl apply -f https://k8s.io/examples/application/deployment.yaml
   ```

2. **Configure Ingress**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: sample-ingress
     annotations:
       kubernetes.io/ingress.class: alb
       alb.ingress.kubernetes.io/scheme: internet-facing
   spec:
     rules:
     - http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: sample-service
               port:
                 number: 80
   ```

3. **Set up GitOps with ArgoCD/Flux**
4. **Configure HPA for autoscaling**

---

## Deploy Data Pipeline in 20 Minutes

Deploy a serverless data processing pipeline with Lambda, S3, and monitoring.

### Architecture Overview

```
    +------------+     +------------+     +------------+
    |   S3       | --> |  Lambda    | --> |   S3       |
    |  (Input)   |     | (Process)  |     |  (Output)  |
    +------------+     +-----+------+     +------------+
                             |
                       +-----v------+
                       |    SQS     |
                       |   (DLQ)    |
                       +------------+
                             |
    +------------------------+------------------------+
    |                        |                        |
    +--------v------+  +-----v--------+  +------------v---+
    |  CloudWatch   |  |    SNS       |  |    DynamoDB    |
    |   Logs        |  |   Alerts     |  |    State       |
    +---------------+  +--------------+  +----------------+
```

### Components Deployed

| Component | Resources | Estimated Time |
|-----------|-----------|----------------|
| VPC | VPC, Subnets (for VPC-connected Lambda) | 5 min |
| Security Groups | Lambda SG | 2 min |
| IAM | Lambda Execution Roles | 3 min |
| Lambda | Processing Functions | 5 min |
| API Gateway | REST API Endpoints | 4 min |
| Monitoring | Logs, Dashboards, Alarms | 3 min |

### Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$50 |
| Staging | ~$100 |
| Production | ~$300+ (scales with usage) |

### Step-by-Step Deployment

#### Step 1: Create Environment (2 minutes)

```bash
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment pipeline-01 \
  --region us-east-1 \
  --template data-pipeline \
  --env-type development
```

#### Step 2: Configure Pipeline Settings (2 minutes)

```bash
# Customize Lambda configuration
cat >> stacks/orgs/mycompany/dev/pipeline-01/vars.yaml << 'EOF'

vars:
  lambda:
    runtime: "python3.11"
    memory_size: 256
    timeout: 60
    reserved_concurrency: 10

  pipeline:
    batch_size: 100
    retry_attempts: 3
    dlq_enabled: true
EOF
```

#### Step 3: Deploy Infrastructure (15 minutes)

```bash
./scripts/deploy-stack.sh \
  --template data-pipeline \
  --stack mycompany-dev-pipeline-01 \
  --auto-approve
```

#### Step 4: Verify Deployment (1 minute)

```bash
# List Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `mycompany-dev-pipeline`)].FunctionName'

# Check API Gateway
aws apigateway get-rest-apis --query 'items[?name==`mycompany-dev-pipeline-01-api`]'

# View Lambda outputs
atmos terraform output lambda -s mycompany-dev-pipeline-01
```

### Verification Checklist

- [ ] Lambda functions created
- [ ] API Gateway endpoints accessible
- [ ] S3 event triggers configured
- [ ] CloudWatch log groups created
- [ ] DLQ configured for failed events
- [ ] Monitoring alarms active

---

## Deploy Serverless API in 10 Minutes

Deploy a lightweight serverless REST API with Lambda and API Gateway.

### Architecture Overview

```
    +------------+     +------------+     +------------+
    |  Client    | --> | API Gateway| --> |  Lambda    |
    +------------+     +-----+------+     +-----+------+
                             |                  |
                       +-----v------+     +-----v------+
                       | CloudWatch |     | DynamoDB   |
                       +------------+     +------------+
```

### Components Deployed

| Component | Resources | Estimated Time |
|-----------|-----------|----------------|
| VPC | Minimal VPC | 3 min |
| Security Groups | API SG | 1 min |
| IAM | Lambda Roles | 2 min |
| Lambda | API Functions | 2 min |
| API Gateway | REST/HTTP API | 2 min |
| Monitoring | Logs, Basic Alarms | 1 min |

### Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$20 |
| Staging | ~$40 |
| Production | ~$100+ (scales with usage) |

### Step-by-Step Deployment

#### Step 1: Create and Deploy (8 minutes)

```bash
# Create environment
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment api-01 \
  --region us-east-1 \
  --template serverless-api \
  --env-type development

# Deploy
./scripts/deploy-stack.sh \
  --template serverless-api \
  --stack mycompany-dev-api-01 \
  --auto-approve
```

#### Step 2: Get API Endpoint (1 minute)

```bash
# Get API Gateway URL
API_URL=$(atmos terraform output apigateway -s mycompany-dev-api-01 | grep invoke_url | cut -d'"' -f2)
echo "API URL: $API_URL"

# Test the API
curl -X GET "$API_URL/health"

# Expected response:
# {"status": "healthy", "timestamp": "2024-01-01T00:00:00Z"}
```

#### Step 3: Verify (1 minute)

```bash
# Check Lambda function
aws lambda invoke \
  --function-name mycompany-dev-api-01-handler \
  --payload '{"httpMethod": "GET", "path": "/health"}' \
  response.json

cat response.json
```

### Verification Checklist

- [ ] API Gateway deployed and accessible
- [ ] Lambda function responding
- [ ] CloudWatch logs capturing requests
- [ ] Custom domain configured (if applicable)

---

## Deploy Batch Processing in 25 Minutes

Deploy a batch job processing infrastructure with Lambda, Step Functions, and monitoring.

### Architecture Overview

```
    +------------+     +---------------+     +------------+
    | EventBridge| --> | Step Functions| --> |  Lambda    |
    | (Schedule) |     |   (Workflow)  |     | (Process)  |
    +------------+     +-------+-------+     +-----+------+
                               |                   |
                         +-----v------+      +-----v------+
                         |    SNS     |      |     S3     |
                         | (Notify)   |      |  (Output)  |
                         +------------+      +------------+
```

### Components Deployed

| Component | Resources | Estimated Time |
|-----------|-----------|----------------|
| VPC | VPC with private subnets | 5 min |
| Security Groups | Batch processing SGs | 2 min |
| IAM | Step Functions, Lambda Roles | 3 min |
| Lambda | Processing Functions | 5 min |
| Step Functions | State Machine | 5 min |
| Monitoring | Dashboards, Execution Logs | 3 min |

### Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | ~$30 |
| Staging | ~$80 |
| Production | ~$200+ (scales with executions) |

### Step-by-Step Deployment

#### Step 1: Create Environment (2 minutes)

```bash
./scripts/new-environment.sh \
  --tenant mycompany \
  --account dev \
  --environment batch-01 \
  --region us-east-1 \
  --template batch-processing \
  --env-type development
```

#### Step 2: Configure Batch Settings (3 minutes)

```bash
cat >> stacks/orgs/mycompany/dev/batch-01/vars.yaml << 'EOF'

vars:
  batch:
    schedule: "rate(1 hour)"
    timeout_minutes: 30
    max_concurrency: 5
    retry_policy:
      max_attempts: 3
      backoff_rate: 2
EOF
```

#### Step 3: Deploy Infrastructure (18 minutes)

```bash
./scripts/deploy-stack.sh \
  --template batch-processing \
  --stack mycompany-dev-batch-01 \
  --auto-approve
```

#### Step 4: Verify and Test (2 minutes)

```bash
# List Step Functions
aws stepfunctions list-state-machines \
  --query 'stateMachines[?contains(name, `mycompany-dev-batch`)].name'

# Start an execution
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:$AWS_ACCOUNT_ID:stateMachine:mycompany-dev-batch-01 \
  --input '{"batch_id": "test-001"}'

# Check execution status
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:$AWS_ACCOUNT_ID:stateMachine:mycompany-dev-batch-01 \
  --query 'executions[0].status'
```

### Verification Checklist

- [ ] Step Functions state machine created
- [ ] Lambda functions deployed
- [ ] EventBridge schedule configured
- [ ] SNS notifications working
- [ ] CloudWatch logs capturing executions
- [ ] Error handling and retries configured

---

## Troubleshooting Common Issues

### AWS Credentials

```bash
# Issue: "Unable to locate credentials"
# Solution:
aws configure
# Or set environment variables:
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
```

### Terraform State Lock

```bash
# Issue: "Error acquiring the state lock"
# Solution:
terraform force-unlock <LOCK_ID>
# Or wait for the other operation to complete
```

### EKS Connection Issues

```bash
# Issue: "Unable to connect to the server"
# Solution:
aws eks update-kubeconfig --name <cluster-name> --region <region>
# Check cluster status:
aws eks describe-cluster --name <cluster-name> --query 'cluster.status'
```

### Component Not Found

```bash
# Issue: "Component not found in stack"
# Solution: Check component exists
ls components/terraform/
# Validate stack configuration:
atmos validate stacks
```

### Deployment Timeout

```bash
# Issue: Long-running deployment
# Solution: Check AWS Console for resource status
# For EKS, it's normal to take 15-20 minutes
# Monitor progress:
aws eks describe-cluster --name <cluster-name> --query 'cluster.status'
```

---

## Quick Reference Card

### Common Commands

```bash
# Create new environment
./scripts/new-environment.sh --interactive

# Deploy template
./scripts/deploy-stack.sh --template <template> --stack <stack> --auto-approve

# Validate before deploying
atmos validate stacks

# Plan changes
atmos terraform plan <component> -s <stack>

# Apply changes
atmos terraform apply <component> -s <stack>

# View outputs
atmos terraform output <component> -s <stack>

# Destroy environment
atmos workflow destroy-environment -f destroy-environment.yaml \
  tenant=<tenant> account=<account> environment=<env>
```

### Stack Naming Convention

```
<tenant>-<account>-<environment>
Example: mycompany-dev-webapp-01
```

### Component Deployment Order

1. VPC (always first)
2. Security Groups
3. IAM
4. Compute (EKS/EC2/Lambda)
5. Database (RDS/DynamoDB)
6. Add-ons (EKS add-ons, API Gateway)
7. Monitoring (always last)

---

## Getting Help

- **Documentation**: See `/docs/DEPLOYMENT_GUIDE.md` for detailed instructions
- **FAQ**: See `/docs/FAQ.md` for common questions
- **Operations**: See `/docs/OPERATIONS_GUIDE.md` for day-2 operations
- **Support**: Contact platform-team@example.com

---

*Last Updated: 2024-12-02*
