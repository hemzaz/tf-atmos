# Cost Estimation Guide

Comprehensive cost analysis and estimation for the Terraform/Atmos infrastructure platform.

## Table of Contents

1. [Cost Summary](#cost-summary)
2. [Cost by Environment](#cost-by-environment)
3. [Cost by Component](#cost-by-component)
4. [Cost Optimization Strategies](#cost-optimization-strategies)
5. [Cost Calculator](#cost-calculator)
6. [Savings Opportunities](#savings-opportunities)
7. [Cost Monitoring](#cost-monitoring)

---

## Cost Summary

### Monthly Cost Overview

| Environment | Monthly Cost | Annual Cost | Cost Per Day |
|------------|--------------|-------------|--------------|
| **Development** | $495 | $5,940 | $16.50 |
| **Staging** | $1,195 | $14,340 | $39.83 |
| **Production** | $6,135 | $73,620 | $204.50 |
| **Total** | **$7,825** | **$93,900** | **$260.83** |

### Cost Breakdown by Category

```
Production Environment ($6,135/month):
├── Compute (EKS)        $4,000 (65%)
├── Database (RDS)       $1,500 (24%)
├── Storage              $500   (8%)
├── Network              $135   (2%)
└── Other Services       $0     (0%)

Staging Environment ($1,195/month):
├── Compute (EKS)        $800   (67%)
├── Database (RDS)       $200   (17%)
├── Storage              $150   (13%)
├── Network              $45    (4%)
└── Other Services       $0     (0%)

Development Environment ($495/month):
├── Compute (EKS)        $300   (61%)
├── Database (RDS)       $100   (20%)
├── Storage              $50    (10%)
├── Network              $45    (9%)
└── Other Services       $0     (0%)
```

---

## Cost by Environment

### Development Environment: $495/month

#### Compute (EKS): $300/month

**Node Groups:**
```yaml
Configuration:
  Strategy: 70% Spot, 30% On-Demand
  Node Count: 1-10 (typically 3-5 active)
  Instance Types: t3.medium

Cost Breakdown:
  Spot Instances (3x t3.medium):
    - $0.0104/hour × 3 × 730 hours × 70% = $160/month
  On-Demand Instances (2x t3.medium):
    - $0.0416/hour × 2 × 730 hours × 30% = $140/month

Total Compute: $300/month
```

**Auto-Shutdown Schedule:**
- Weekdays: 8am-8pm (12 hours)
- Weekends: Off
- Effective hours: ~260 hours/month (instead of 730)
- Potential savings: $185/month with auto-shutdown

#### Database (RDS): $100/month

**Configuration:**
```yaml
Type: Aurora Serverless v2
Capacity: 0.5-2 ACU
Auto-pause: 10 minutes
Actual Usage: ~50 ACU-hours/month

Cost Breakdown:
  ACU Hours: 50 × $0.12 = $6/month
  Storage: 20 GB × $0.10 = $2/month
  I/O: ~1M requests × $0.20/1M = $0.20/month
  Backups: 20 GB × $0.021 = $0.42/month

Total Database: ~$100/month (with overhead)
```

#### Storage: $50/month

```yaml
EBS Volumes (gp3):
  - 5 volumes × 50 GB × $0.08/GB = $20/month
  - IOPS: Baseline included
  - Throughput: Baseline included

S3 Buckets:
  - Standard: 100 GB × $0.023/GB = $2.30/month
  - Intelligent Tiering: 50 GB × $0.023/GB = $1.15/month
  - Requests: ~100K × $0.005/10K = $0.50/month

Snapshots:
  - EBS Snapshots: 50 GB × $0.05/GB = $2.50/month
  - RDS Snapshots: Included in RDS cost

Total Storage: $50/month
```

#### Network: $45/month

```yaml
NAT Gateway:
  - Single NAT Gateway: $0.045/hour × 730 = $32.85/month
  - Data Processing: 10 GB × $0.045/GB = $0.45/month

Load Balancers:
  - ALB: $0.0225/hour × 730 = $16.43/month
  - LCU Hours: Minimal usage

Data Transfer:
  - Out to Internet: 5 GB × $0.09/GB = $0.45/month
  - Inter-AZ: Minimal

Total Network: $45/month
```

---

### Staging Environment: $1,195/month

#### Compute (EKS): $800/month

**Node Groups:**
```yaml
Configuration:
  Strategy: 50% Spot, 30% Reserved, 20% On-Demand
  Node Count: 2-15 (typically 5-8 active)
  Instance Types: t3.large

Cost Breakdown:
  Spot Instances (4x t3.large):
    - $0.0208/hour × 4 × 730 hours × 50% = $304/month

  Reserved Instances (3x t3.large, 1-year partial upfront):
    - $0.0291/hour × 3 × 730 hours × 30% = $191/month

  On-Demand Instances (2x t3.large):
    - $0.0832/hour × 2 × 730 hours × 20% = $243/month

Total Compute: $800/month
```

**Business Hours Schedule:**
- Weekdays: 6am-10pm (16 hours)
- Weekends: 8am-6pm (10 hours)
- Potential savings: $250/month with scheduling

#### Database (RDS): $200/month

**Configuration:**
```yaml
Type: Aurora MySQL
Instance: db.t3.medium
Multi-AZ: No
Read Replicas: 0

Cost Breakdown:
  Instance: $0.082/hour × 730 = $60/month
  Storage: 100 GB × $0.10/GB = $10/month
  I/O: ~5M requests × $0.20/1M = $1/month
  Backups: 100 GB × $0.021/GB = $2.10/month
  Enhanced Monitoring: $1.40/month

Total Database: $200/month
```

#### Storage: $150/month

```yaml
EBS Volumes (gp3):
  - 10 volumes × 100 GB × $0.08/GB = $80/month
  - IOPS: 5,000 provisioned × $0.005 = $25/month
  - Throughput: Baseline included

S3 Buckets:
  - Standard: 500 GB × $0.023/GB = $11.50/month
  - Intelligent Tiering: 200 GB × $0.023/GB = $4.60/month
  - Requests: ~500K × $0.005/10K = $2.50/month

Snapshots:
  - EBS Snapshots: 100 GB × $0.05/GB = $5/month
  - RDS Snapshots: 50 GB × $0.021/GB = $1.05/month

Total Storage: $150/month
```

#### Network: $45/month

```yaml
NAT Gateway:
  - Single NAT Gateway: $32.85/month
  - Data Processing: 20 GB × $0.045/GB = $0.90/month

Load Balancers:
  - ALB: $16.43/month
  - NLB: Not used

Data Transfer:
  - Out to Internet: 10 GB × $0.09/GB = $0.90/month

Total Network: $45/month
```

---

### Production Environment: $6,135/month

#### Compute (EKS): $4,000/month

**Node Groups:**
```yaml
Configuration:
  Strategy: 60% Reserved, 30% Savings Plans, 10% On-Demand
  Node Count: 3-30 (typically 15-20 active)
  Instance Types: m5.xlarge

Cost Breakdown:
  Reserved Instances (10x m5.xlarge, 3-year all upfront):
    - $0.134/hour × 10 × 730 hours × 60% = $1,957/month

  Savings Plans (6x m5.xlarge, 1-year):
    - $0.134/hour × 6 × 730 hours × 30% = $752/month

  On-Demand Instances (4x m5.xlarge):
    - $0.192/hour × 4 × 730 hours × 10% = $561/month

  EKS Control Plane:
    - $0.10/hour × 730 = $73/month × 2 clusters = $146/month

  Karpenter-managed Spot:
    - Variable: ~$584/month average

Total Compute: $4,000/month
```

#### Database (RDS): $1,500/month

**Configuration:**
```yaml
Type: Aurora MySQL
Instance: db.r5.xlarge (writer) + 2× db.r5.large (readers)
Multi-AZ: Yes
Backup Retention: 7 days

Cost Breakdown:
  Writer Instance: $0.29/hour × 730 = $212/month
  Reader Replicas: $0.145/hour × 2 × 730 = $212/month
  Multi-AZ Standby: $0.29/hour × 730 = $212/month
  Storage: 500 GB × $0.10/GB = $50/month
  I/O: ~50M requests × $0.20/1M = $10/month
  Backups: 500 GB × $0.021/GB = $10.50/month
  Enhanced Monitoring: $4.20/month
  Performance Insights: $3.50/month

Reserved Instance Discount: -30%
Total Database: $1,500/month
```

#### Storage: $500/month

```yaml
EBS Volumes:
  - gp3: 30 volumes × 200 GB × $0.08/GB = $480/month
  - io2: 5 volumes × 100 GB × $0.125/GB = $62.50/month
  - IOPS: 20,000 provisioned × $0.065 = $130/month
  - Throughput: 1,000 MB/s × $0.04 = $40/month

S3 Buckets:
  - Standard: 2 TB × $0.023/GB = $47.10/month
  - Standard-IA: 5 TB × $0.0125/GB = $64/month
  - Intelligent Tiering: 3 TB × $0.023/GB = $70.60/month
  - Glacier: 10 TB × $0.004/GB = $41/month

Snapshots:
  - EBS Snapshots: 500 GB × $0.05/GB = $25/month
  - RDS Snapshots: 200 GB × $0.021/GB = $4.20/month

Total Storage: $500/month
```

#### Network: $135/month

```yaml
NAT Gateways:
  - 3× NAT Gateways (one per AZ): 3 × $32.85 = $98.55/month
  - Data Processing: 100 GB × $0.045/GB = $4.50/month

Load Balancers:
  - ALB: 2× $16.43 = $32.86/month
  - NLB: $16.43/month
  - LCU Hours: Variable

VPC Endpoints:
  - S3 Gateway: Free
  - DynamoDB Gateway: Free
  - Interface Endpoints: 3 × $7.30 = $21.90/month

Data Transfer:
  - Out to Internet: 100 GB × $0.09/GB = $9/month
  - CloudFront: 500 GB × $0.085/GB = $42.50/month
  - Inter-AZ: Minimal

Total Network: $135/month
```

---

## Cost by Component

### VPC Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| NAT Gateway | $33 | $33 | $99 |
| VPC Endpoints | $0 | $0 | $22 |
| Flow Logs | $5 | $10 | $25 |
| **Total** | **$38** | **$43** | **$146** |

### EKS Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| Control Plane | $73 | $73 | $146 |
| Worker Nodes | $227 | $727 | $3,854 |
| **Total** | **$300** | **$800** | **$4,000** |

### RDS Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| Instances | $8 | $74 | $848 |
| Storage | $2 | $10 | $50 |
| I/O | $0.20 | $1 | $10 |
| Backups | $0.42 | $2.10 | $10.50 |
| **Total** | **$100** | **$200** | **$1,500** |

### Monitoring Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| CloudWatch Logs | $5 | $15 | $50 |
| CloudWatch Metrics | $2 | $5 | $20 |
| X-Ray | $0 | $2 | $10 |
| Dashboards | $0 | $3 | $9 |
| **Total** | **$7** | **$25** | **$89** |

### Lambda Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| Invocations | $1 | $5 | $20 |
| Duration | $2 | $10 | $40 |
| **Total** | **$3** | **$15** | **$60** |

### API Gateway Component

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| API Calls | $3.50 | $15 | $70 |
| Data Transfer | $0.50 | $2 | $10 |
| **Total** | **$4** | **$17** | **$80** |

---

## Cost Optimization Strategies

### 1. Compute Optimization (Save 40-60%)

#### Use Spot Instances

```yaml
# Dev: 70% Spot
Savings: $270/month (90% cost reduction on Spot portion)

# Staging: 50% Spot
Savings: $400/month (70% cost reduction on Spot portion)

# Production: 20% Spot
Savings: $640/month (70% cost reduction on Spot portion)

Total Savings: $1,310/month
```

#### Reserved Instances & Savings Plans

```yaml
# 1-year Reserved Instance: 42% savings
# 3-year Reserved Instance: 62% savings
# Compute Savings Plans: 40% savings

Production Recommendations:
- Reserve 60% of baseline capacity (3-year RI): Save $1,200/month
- Savings Plans for 30% (1-year): Save $450/month

Total Savings: $1,650/month
```

#### Auto-Scaling & Scheduling

```yaml
Development:
  Schedule: Shutdown nights/weekends
  Savings: 64% reduction in hours
  Monthly Savings: $185/month

Staging:
  Schedule: Business hours only (16h weekdays, 10h weekends)
  Savings: 45% reduction in hours
  Monthly Savings: $250/month

Total Savings: $435/month
```

#### Karpenter for Dynamic Provisioning

```yaml
Benefits:
  - Better bin packing: 15-20% reduction in nodes
  - Faster scaling: Reduces over-provisioning
  - Automatic right-sizing

Estimated Savings: $400/month across all environments
```

### 2. Database Optimization (Save 30-50%)

#### Aurora Serverless for Non-Production

```yaml
Development:
  Current: Aurora Provisioned = $100/month
  Proposed: Aurora Serverless v2 = $20/month
  Savings: $80/month

Staging (during off-hours):
  Enable auto-pause during nights: $50/month savings
```

#### Read Replica Right-Sizing

```yaml
Production:
  Current: 2× db.r5.large replicas = $212/month
  Optimized: 2× db.t3.large replicas = $120/month
  Savings: $92/month
```

#### Reserved Instances for Production

```yaml
Production Database:
  1-year RI: Save 30% = $450/month
  3-year RI: Save 60% = $900/month

Recommendation: 3-year RI
Savings: $900/month
```

### 3. Storage Optimization (Save 25-40%)

#### gp3 Instead of gp2

```yaml
Migration:
  All gp2 volumes → gp3
  Savings: 20% on volume costs

Development: $4/month
Staging: $16/month
Production: $96/month

Total Savings: $116/month
```

#### S3 Lifecycle Policies

```yaml
Policy:
  - Standard → Intelligent Tiering: Immediate
  - Intelligent Tiering → Glacier: 90 days
  - Delete old versions: 180 days

Estimated Savings:
  Development: $10/month
  Staging: $30/month
  Production: $100/month

Total Savings: $140/month
```

#### EBS Snapshot Management

```yaml
Retention Policy:
  - Daily: 7 days
  - Weekly: 4 weeks
  - Monthly: 3 months
  - Delete older snapshots

Estimated Savings: $50/month
```

### 4. Network Optimization (Save 30-50%)

#### VPC Endpoints

```yaml
Use VPC Endpoints for:
  - S3 (free gateway endpoint)
  - DynamoDB (free gateway endpoint)
  - ECR ($7.30/month per AZ)

Savings on Data Transfer:
  Development: $10/month
  Staging: $15/month
  Production: $50/month

Cost of Endpoints: $22/month
Net Savings: $53/month
```

#### Consolidate NAT Gateways

```yaml
Development:
  Current: 3× NAT Gateways = $99/month
  Optimized: 1× NAT Gateway = $33/month
  Savings: $66/month

Staging:
  Current: 3× NAT Gateways = $99/month
  Optimized: 1× NAT Gateway = $33/month
  Savings: $66/month

Total Savings: $132/month
```

#### CloudFront for Static Assets

```yaml
Benefits:
  - Reduced origin load
  - Lower data transfer costs
  - Better performance

Estimated Savings: $30/month
```

### 5. Total Potential Savings

| Optimization | Monthly Savings | Annual Savings |
|-------------|----------------|----------------|
| Spot Instances | $1,310 | $15,720 |
| Reserved Instances | $1,650 | $19,800 |
| Auto-Scaling/Scheduling | $435 | $5,220 |
| Karpenter | $400 | $4,800 |
| Aurora Serverless | $130 | $1,560 |
| Database RI | $900 | $10,800 |
| gp3 Migration | $116 | $1,392 |
| S3 Lifecycle | $140 | $1,680 |
| Snapshot Management | $50 | $600 |
| VPC Endpoints | $53 | $636 |
| NAT Consolidation | $132 | $1,584 |
| CloudFront | $30 | $360 |
| **Total** | **$5,346** | **$64,152** |

**Optimized Monthly Cost: $2,479** (68% reduction from $7,825)

---

## Cost Calculator

### Calculate Your Environment Cost

```bash
# Use the cost calculator script
./scripts/cost-calculator.sh \
  --environment prod \
  --region us-east-1 \
  --node-count 15 \
  --instance-type m5.xlarge \
  --database-class db.r5.xlarge \
  --storage-size 500

# Example output:
Environment: Production
Region: us-east-1

Compute:
  - 15× m5.xlarge On-Demand: $2,102/month
  - EKS Control Plane: $73/month
  Total: $2,175/month

Database:
  - db.r5.xlarge: $212/month
  - Storage (500 GB): $50/month
  Total: $262/month

Storage:
  - EBS (1,500 GB gp3): $120/month
  - S3 (500 GB): $11.50/month
  Total: $131.50/month

Network:
  - 3× NAT Gateways: $99/month
  - ALB: $16.43/month
  Total: $115.43/month

TOTAL ESTIMATED COST: $2,683.93/month
```

### Online Calculator Template

Use the AWS Pricing Calculator:
1. Go to https://calculator.aws/
2. Add services:
   - Amazon EKS
   - Amazon EC2
   - Amazon RDS
   - Amazon S3
   - Amazon VPC
3. Configure based on your requirements
4. Save and share estimate

---

## Savings Opportunities

### Quick Wins (Implement in 1 day)

1. **Delete Unused Resources** - Savings: $200/month
   - Unattached EBS volumes
   - Unused Elastic IPs
   - Old snapshots
   - Unused security groups

2. **Enable S3 Intelligent Tiering** - Savings: $100/month
   ```bash
   aws s3api put-bucket-intelligent-tiering-configuration \
     --bucket my-bucket \
     --id intelligent-tiering \
     --intelligent-tiering-configuration file://config.json
   ```

3. **Migrate to gp3** - Savings: $116/month
   ```bash
   ./scripts/migrate-to-gp3.sh
   ```

### Medium-Term (Implement in 1 week)

1. **Deploy Karpenter** - Savings: $400/month
2. **Enable Auto-Scaling** - Savings: $435/month
3. **Consolidate NAT Gateways** - Savings: $132/month
4. **Aurora Serverless for Dev** - Savings: $80/month

### Long-Term (Implement in 1 month)

1. **Purchase Reserved Instances** - Savings: $1,650/month
2. **Implement Savings Plans** - Savings: $450/month
3. **Deploy Spot Instances** - Savings: $1,310/month
4. **Database Reserved Instances** - Savings: $900/month

---

## Cost Monitoring

### Set Up Budget Alerts

```bash
# Create monthly budget
aws budgets create-budget \
  --account-id ${AWS_ACCOUNT_ID} \
  --budget file://budget.json

# budget.json
{
  "BudgetName": "Monthly-Infrastructure-Budget",
  "BudgetLimit": {
    "Amount": "8000",
    "Unit": "USD"
  },
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "TimePeriod": {
    "Start": "2025-01-01T00:00:00Z"
  }
}

# Create alerts at 50%, 80%, 100%
aws budgets create-notification \
  --account-id ${AWS_ACCOUNT_ID} \
  --budget-name Monthly-Infrastructure-Budget \
  --notification file://notification-80.json \
  --subscribers file://subscribers.json
```

### Daily Cost Reports

```bash
# Generate daily cost report
./scripts/daily-cost-report.sh

# Output:
Today's Cost: $260.83
Yesterday: $255.20
Change: +$5.63 (+2.2%)

Top Services:
1. Amazon EC2: $180.50 (69%)
2. Amazon RDS: $50.00 (19%)
3. Amazon S3: $15.33 (6%)
4. Other: $15.00 (6%)
```

### Cost Anomaly Detection

```bash
# Enable cost anomaly detection
aws ce create-anomaly-monitor \
  --monitor-name "Infrastructure-Anomaly-Monitor" \
  --monitor-type DIMENSIONAL \
  --monitor-dimension SERVICE

aws ce create-anomaly-subscription \
  --subscription-name "Infrastructure-Anomaly-Alerts" \
  --monitor-arn <monitor-arn> \
  --threshold 100 \
  --frequency IMMEDIATE \
  --subscribers file://subscribers.json
```

### Weekly Cost Review

```bash
# Generate weekly report
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json | \
  jq -r '.ResultsByTime[] | "\(.TimePeriod.Start): $\(.Total.BlendedCost.Amount)"'
```

---

## Additional Resources

- [AWS Pricing Calculator](https://calculator.aws/)
- [AWS Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/)
- [Cost Optimization Best Practices](https://aws.amazon.com/pricing/cost-optimization/)
- [Architecture Cost Analysis](./architecture/CLOUD_ARCHITECTURE_OPTIMIZATION_PLAN.md)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**Next Review**: Monthly
**Cost Baseline Date**: 2025-12-02

**Note**: All costs are estimates based on us-east-1 pricing and typical usage patterns. Actual costs may vary based on usage, region, and AWS pricing changes.
