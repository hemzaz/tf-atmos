# Data Environment Template

This template provides a standardized configuration for Data-focused environments.

## Purpose

Data environments are designed for:
- Data processing, analytics, and warehousing
- ETL/ELT pipelines
- Machine learning and AI workloads
- High-volume data storage and retrieval

## Features

- **VPC Configuration**:
  - Optimized VPC with private subnets for data processing
  - Transit Gateway connections to data sources
  - VPC endpoints for AWS data services
  - High throughput networking

- **Compute Resources**:
  - Data processing optimized instances
  - Elastic clusters for variable workloads
  - Spot instances for batch processing
  - GPU instances for ML workloads

- **Storage Resources**:
  - Optimized S3 buckets with lifecycle policies
  - EFS for shared storage
  - Storage optimized RDS/Aurora instances
  - Redshift/EMR/Athena integrations

- **Security**:
  - Data-specific security groups
  - Data access audit logging
  - Data encryption in transit and at rest
  - Medium to long retention periods for logs (60+ days)

- **Monitoring**:
  - Data pipeline monitoring dashboards
  - Storage usage and performance metrics
  - ETL job status dashboards
  - Cost optimization metrics

## Usage

To create a new data environment:

```bash
# Using the environment creation workflow
atmos workflow create-environment \
  --template=data \
  --tenant=<tenant> \
  --account=<account> \
  --environment=<env-name> \
  --vpc-cidr=<cidr-block>

# Alternative: Using cookiecutter directly
cookiecutter templates/cookiecutter-environment \
  tenant=<tenant> \
  account=<account> \
  env_name=<env-name> \
  env_type=data \
  vpc_cidr=<cidr-block>
```

## Key Configuration Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| vpc_cidr | 10.0.0.0/16 | VPC CIDR block |
| eks_node_instance_type | r5.2xlarge | EKS node instance type (memory optimized) |
| eks_node_min_count | 2 | Minimum number of EKS nodes |
| eks_node_max_count | 8 | Maximum number of EKS nodes |
| retention_days | 60 | Log retention period in days |
| s3_data_lifecycle | true | Whether to enable S3 lifecycle policies |
| rds_instance_type | r5.large | RDS instance type |
| enable_redshift | true | Whether to enable Redshift |
| enable_emr | true | Whether to enable EMR |

## Data Services

This template includes configurations for:
- AWS Glue for ETL
- Amazon Redshift for data warehousing
- Amazon Athena for SQL queries
- Amazon QuickSight for visualization
- Amazon EMR for big data processing
- AWS Data Pipeline for orchestration