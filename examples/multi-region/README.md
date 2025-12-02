# Multi-Region Deployment Example

This example demonstrates deploying infrastructure across multiple AWS regions for disaster recovery and global availability.

## Overview

The multi-region deployment includes:

### Primary Region (eu-west-2)
- Full production infrastructure
- Active workloads
- Primary database (RDS)

### Secondary Region (us-east-1)
- Hot standby infrastructure
- Read replicas
- DR target

### Cross-Region Components
- S3 cross-region replication
- DynamoDB global tables
- Route53 health checks and failover

## Architecture

```
+-----------------------------------+    +-----------------------------------+
|         Primary Region            |    |        Secondary Region           |
|         (eu-west-2)               |    |         (us-east-1)               |
+-----------------------------------+    +-----------------------------------+
|                                   |    |                                   |
|  +---------------------------+    |    |  +---------------------------+    |
|  |         Main VPC          |    |    |  |         Main VPC          |    |
|  |      10.20.0.0/16         |    |    |  |      10.30.0.0/16         |    |
|  +---------------------------+    |    |  +---------------------------+    |
|  | - EKS Cluster (Active)    |    |    |  | - EKS Cluster (Standby)   |    |
|  | - RDS Primary             |<-------->  | - RDS Read Replica        |    |
|  | - ElastiCache Primary     |    |    |  | - ElastiCache Standby     |    |
|  +---------------------------+    |    |  +---------------------------+    |
|                                   |    |                                   |
|  +---------------------------+    |    |  +---------------------------+    |
|  |    S3 State Bucket        |<-------->  |    S3 State Bucket        |    |
|  | (Cross-region replication)|    |    |  | (Replication target)      |    |
|  +---------------------------+    |    |  +---------------------------+    |
|                                   |    |                                   |
|  +---------------------------+    |    |  +---------------------------+    |
|  |   DynamoDB Global Table   |<-------->  |   DynamoDB Global Table   |    |
|  +---------------------------+    |    |  +---------------------------+    |
|                                   |    |                                   |
+-----------------------------------+    +-----------------------------------+
                    |                                     |
                    +-------------------------------------+
                                     |
                    +-------------------------------------+
                    |           Route53                   |
                    |   (Health checks + Failover DNS)    |
                    +-------------------------------------+
```

## Deployment Steps

### 1. Deploy Primary Region

```bash
# Set primary region
export AWS_REGION=eu-west-2
export PRIMARY_REGION=eu-west-2
export SECONDARY_REGION=us-east-1

# Deploy primary region
atmos workflow deploy -f deploy-full-stack.yaml \
  tenant=acme account=prod environment=production \
  region=eu-west-2 \
  auto_approve=true
```

### 2. Configure Cross-Region Replication

```bash
# Enable S3 cross-region replication
aws s3api put-bucket-replication \
  --bucket acme-prod-production-terraform-state \
  --replication-configuration file://replication-config.json

# Create DynamoDB global table
aws dynamodb create-global-table \
  --global-table-name acme-prod-production-terraform-locks \
  --replication-group RegionName=eu-west-2 RegionName=us-east-1
```

### 3. Deploy Secondary Region

```bash
# Deploy secondary region (DR)
atmos workflow deploy -f deploy-full-stack.yaml \
  tenant=acme account=prod environment=production-dr \
  region=us-east-1 \
  auto_approve=true
```

### 4. Configure RDS Read Replica

```bash
# Create cross-region read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier production-dr-main-db \
  --source-db-instance-identifier arn:aws:rds:eu-west-2:123456789012:db:production-main-db \
  --region us-east-1 \
  --db-instance-class db.r5.xlarge \
  --availability-zone us-east-1a
```

### 5. Configure Route53 Failover

```bash
# Create health check for primary
aws route53 create-health-check \
  --caller-reference "primary-health-check-$(date +%s)" \
  --health-check-config '{
    "IPAddress": "PRIMARY_ALB_IP",
    "Port": 443,
    "Type": "HTTPS",
    "ResourcePath": "/health",
    "FullyQualifiedDomainName": "api.example.com",
    "RequestInterval": 30,
    "FailureThreshold": 3
  }'

# Create failover record set
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch file://failover-records.json
```

## Stack Configuration

### Primary Region Stack

```yaml
# stacks/orgs/acme/prod/eu-west-2/production.yaml
vars:
  tenant: acme
  account: prod
  environment: production
  region: eu-west-2
  is_primary_region: true
  dr_region: us-east-1

components:
  terraform:
    rds/main:
      vars:
        # Enable cross-region backup
        backup_retention_period: 30
        copy_tags_to_snapshot: true
```

### Secondary Region Stack

```yaml
# stacks/orgs/acme/prod/us-east-1/production-dr.yaml
vars:
  tenant: acme
  account: prod
  environment: production-dr
  region: us-east-1
  is_primary_region: false
  primary_region: eu-west-2

components:
  terraform:
    rds/main:
      vars:
        # Read replica configuration
        replicate_source_db: "arn:aws:rds:eu-west-2:123456789012:db:production-main-db"
```

## Failover Procedures

### Planned Failover

```bash
# 1. Promote secondary RDS to primary
aws rds promote-read-replica \
  --db-instance-identifier production-dr-main-db \
  --region us-east-1

# 2. Update Route53 weights
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "SetIdentifier": "secondary",
        "Weight": 100,
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "secondary-alb.us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# 3. Scale up secondary EKS
aws eks update-nodegroup-config \
  --cluster-name production-dr-main \
  --nodegroup-name workers \
  --scaling-config minSize=3,maxSize=12,desiredSize=6 \
  --region us-east-1
```

### Emergency Failover

```bash
# Run DR failover workflow
atmos workflow dr-failover -f disaster-recovery.yaml \
  tenant=acme account=prod environment=production \
  target_region=us-east-1 \
  confirm=true
```

### Failback

```bash
# Run failback workflow
atmos workflow dr-failback -f disaster-recovery.yaml \
  tenant=acme account=prod environment=production \
  confirm=true
```

## Monitoring Multi-Region Setup

### Cross-Region Metrics

```bash
# Check replication lag
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=production-dr-main-db \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

### Health Check Status

```bash
# Check Route53 health check status
aws route53 get-health-check-status \
  --health-check-id ABC123
```

## Cost Considerations

Running multi-region adds approximately:
- RDS read replica: +$300-600/month
- Cross-region data transfer: +$100-500/month (varies by usage)
- Duplicate NAT Gateways: +$200/month
- Duplicate compute (standby): +$500-2000/month

Total additional cost: **~$1,100-3,300/month**

## Best Practices

1. **Regular DR Drills**: Test failover quarterly
2. **Monitor Replication Lag**: Alert on lag > 1 minute
3. **Symmetric Configuration**: Keep regions as similar as possible
4. **Automated Failover**: Use Route53 health checks for automatic DNS failover
5. **Data Consistency**: Understand RPO implications of async replication
