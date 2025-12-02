# Stack Templates

This directory contains production-ready stack templates for common infrastructure patterns. Each template provides a complete, deployable infrastructure configuration that can be customized for specific needs.

## Available Templates

| Template | Description | Cost (Dev) | Cost (Prod) | Deploy Time |
|----------|-------------|------------|-------------|-------------|
| [web-application](#web-application) | 3-tier web application | $150-300/mo | $800-2,500/mo | 25-40 min |
| [microservices-platform](#microservices-platform) | EKS-based microservices | $200-400/mo | $1,500-5,000/mo | 30-45 min |
| [data-pipeline](#data-pipeline) | Kinesis + Glue data processing | $100-250/mo | $800-5,000/mo | 20-35 min |
| [serverless-api](#serverless-api) | Lambda + API Gateway API | $10-50/mo | $200-2,000/mo | 15-25 min |
| [batch-processing](#batch-processing) | AWS Batch job processing | $50-150/mo | $500-5,000/mo | 15-25 min |

## Quick Start

### 1. Import a Template

Create a new stack file that imports the template:

```yaml
# stacks/orgs/myorg/prod/us-east-1.yaml
import:
  - catalog/templates/web-application
  - mixins/production

vars:
  tenant: myorg
  account: prod
  environment: production
  region: us-east-1

  # Required template variables
  app_domain_name: "myapp.example.com"
  route53_zone_id: "Z1234567890ABC"
  app_container_image: "123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:latest"
```

### 2. Preview Changes

```bash
atmos terraform plan web-application/vpc -s myorg-prod-production
atmos terraform plan web-application/rds -s myorg-prod-production
```

### 3. Deploy

```bash
atmos terraform apply web-application/vpc -s myorg-prod-production
atmos terraform apply web-application/securitygroups -s myorg-prod-production
# ... continue with remaining components
```

Or use the workflow:

```bash
atmos workflow deploy-web-application tenant=myorg account=prod environment=production
```

---

## Template Details

### Web Application

**File:** `web-application.yaml`

A complete 3-tier web application infrastructure suitable for most web applications.

#### Architecture

```
                    +----------------+
                    |   CloudFront   |
                    +-------+--------+
                            |
                    +-------v--------+
                    |      WAF       |
                    +-------+--------+
                            |
                    +-------v--------+
                    |      ALB       |
                    +-------+--------+
                            |
              +-------------+-------------+
              |             |             |
        +-----v-----+ +-----v-----+ +-----v-----+
        |  ECS/EC2  | |  ECS/EC2  | |  ECS/EC2  |
        |  (App)    | |  (App)    | |  (App)    |
        +-----+-----+ +-----+-----+ +-----+-----+
              |             |             |
              +-------------+-------------+
                            |
              +-------------+-------------+
              |                           |
        +-----v-----+               +-----v-----+
        |    RDS    |               |ElastiCache|
        |  Aurora   |               |   Redis   |
        +-----------+               +-----------+
```

#### Components

| Component | Description |
|-----------|-------------|
| `web-application/vpc` | VPC with public/private/database subnets |
| `web-application/securitygroups` | Security groups for ALB, app, DB, cache |
| `web-application/acm` | SSL/TLS certificates |
| `web-application/alb` | Application Load Balancer |
| `web-application/waf` | Web Application Firewall |
| `web-application/ecs-cluster` | ECS Fargate cluster |
| `web-application/ecs-service` | ECS service with auto-scaling |
| `web-application/rds` | RDS PostgreSQL database |
| `web-application/elasticache` | ElastiCache Redis cluster |
| `web-application/cloudfront` | CloudFront CDN distribution |
| `web-application/dns` | Route53 DNS records |
| `web-application/monitoring` | CloudWatch dashboards and alarms |

#### Required Variables

```yaml
vars:
  # Domain configuration
  app_domain_name: "example.com"
  route53_zone_id: "Z1234567890ABC"

  # Container configuration
  app_container_image: "123456789.dkr.ecr.us-east-1.amazonaws.com/webapp:latest"
  app_container_port: 8080

  # IAM roles
  ecs_execution_role_arn: "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
  ecs_task_role_arn: "arn:aws:iam::123456789012:role/ecsTaskRole"

  # Secrets
  database_password_secret_arn: "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-password"

  # Notifications
  alarm_email_addresses:
    - "ops@example.com"
```

#### Environment Overrides

```yaml
# Development
vars:
  nat_gateway_strategy: "single"
  db_instance_class: "db.t3.micro"
  db_multi_az: false
  cache_node_type: "cache.t3.micro"
  desired_count: 1

# Production
vars:
  nat_gateway_strategy: "one_per_az"
  db_instance_class: "db.r6g.large"
  db_multi_az: true
  db_deletion_protection: true
  cache_node_type: "cache.r6g.large"
  cache_cluster_mode: true
  desired_count: 3
  autoscaling_max: 20
```

---

### Microservices Platform

**File:** `microservices-platform.yaml`

A complete microservices infrastructure with EKS, service mesh ready, and event-driven architecture.

#### Architecture

```
                    +----------------+
                    |  API Gateway   |
                    +-------+--------+
                            |
                    +-------v--------+
                    |    VPC Link    |
                    +-------+--------+
                            |
        +-------------------+-------------------+
        |                   |                   |
  +-----v-----+       +-----v-----+       +-----v-----+
  | Service A |<----->| Service B |<----->| Service C |
  | (Pod)     |       | (Pod)     |       | (Pod)     |
  +-----+-----+       +-----+-----+       +-----+-----+
        |                   |                   |
        +-------------------+-------------------+
                            |
              +-------------+-------------+
              |             |             |
        +-----v-----+ +-----v-----+ +-----v-----+
        |EventBridge| | DynamoDB  | |ElastiCache|
        |   (Bus)   | | (State)   | |  (Cache)  |
        +-----------+ +-----------+ +-----------+
```

#### Components

| Component | Description |
|-----------|-------------|
| `microservices/vpc` | VPC with large subnets for EKS pods |
| `microservices/eks` | EKS cluster with managed node groups |
| `microservices/eks-addons` | K8s addons (ALB controller, autoscaler, etc.) |
| `microservices/apigateway` | HTTP API Gateway with VPC Link |
| `microservices/eventbridge` | Event bus for async communication |
| `microservices/dynamodb` | DynamoDB tables for state and sagas |
| `microservices/elasticache` | Redis cluster with cluster mode |
| `microservices/monitoring` | Container Insights, X-Ray, dashboards |
| `microservices/secrets` | Secrets Manager for credentials |

#### Required Variables

```yaml
vars:
  # EKS configuration
  eks_kms_key_arn: "arn:aws:kms:us-east-1:123456789012:key/xxx"
  eks_admin_role_arn: "arn:aws:iam::123456789012:role/EKSAdmin"
  ebs_csi_role_arn: "arn:aws:iam::123456789012:role/EBSCSIDriverRole"

  # Cognito (for API auth)
  cognito_user_pool_id: "us-east-1_xxxxx"
  cognito_client_id: "xxxxxxxxxx"

  # Domain
  app_domain_name: "example.com"
  route53_zone_id: "Z1234567890ABC"

  # KMS keys
  dynamodb_kms_key_arn: "arn:aws:kms:..."
  cache_kms_key_id: "arn:aws:kms:..."
  secrets_kms_key_id: "arn:aws:kms:..."
```

#### Node Group Configuration

```yaml
# Development - minimal resources
vars:
  system_node_min: 1
  system_node_max: 2
  app_node_min: 1
  app_node_max: 5
  app_capacity_type: "SPOT"

# Production - high availability
vars:
  system_node_min: 3
  system_node_max: 6
  app_node_min: 5
  app_node_max: 50
  app_capacity_type: "ON_DEMAND"
  spot_node_min: 2
  spot_node_max: 20
```

---

### Data Pipeline

**File:** `data-pipeline.yaml`

A complete data processing pipeline with real-time streaming and batch ETL capabilities.

#### Architecture

```
  Data Sources          Ingestion           Processing           Storage           Analytics
  +-----------+     +---------------+     +-----------+     +---------------+     +---------+
  | Apps/IoT  |---->| Kinesis Data  |---->|  Lambda   |---->| S3 Data Lake  |---->| Athena  |
  | Devices   |     |   Streams     |     | Transform |     | (Raw/Curated) |     | Queries |
  +-----------+     +---------------+     +-----------+     +---------------+     +---------+
                           |                    |                   |
                           v                    v                   v
                    +---------------+     +-----------+     +---------------+
                    |   Firehose    |     |   Glue    |     |  QuickSight   |
                    |   Delivery    |     |  Crawlers |     | Dashboards    |
                    +---------------+     +-----------+     +---------------+
```

#### Components

| Component | Description |
|-----------|-------------|
| `data-pipeline/s3-raw` | S3 bucket for raw data landing zone |
| `data-pipeline/s3-processed` | S3 bucket for transformed data |
| `data-pipeline/s3-curated` | S3 bucket for analytics-ready data |
| `data-pipeline/kinesis-ingest` | Kinesis stream for data ingestion |
| `data-pipeline/kinesis-enriched` | Kinesis stream for enriched data |
| `data-pipeline/lambda-transformer` | Lambda for real-time transformation |
| `data-pipeline/firehose-raw` | Firehose delivery to S3 (Parquet) |
| `data-pipeline/firehose-processed` | Firehose with dynamic partitioning |
| `data-pipeline/glue-database` | Glue Data Catalog database |
| `data-pipeline/glue-crawlers` | Glue crawlers for schema discovery |
| `data-pipeline/athena` | Athena workgroup with saved queries |
| `data-pipeline/step-functions` | ETL workflow orchestration |
| `data-pipeline/eventbridge` | Schedule triggers for pipelines |
| `data-pipeline/monitoring` | Pipeline monitoring and alerts |

#### Required Variables

```yaml
vars:
  # KMS keys
  data_lake_kms_key_id: "arn:aws:kms:..."
  kinesis_kms_key_id: "arn:aws:kms:..."
  athena_kms_key_arn: "arn:aws:kms:..."

  # IAM roles
  glue_crawler_role_arn: "arn:aws:iam::..."
  firehose_kinesis_role_arn: "arn:aws:iam::..."
  firehose_glue_role_arn: "arn:aws:iam::..."
  eventbridge_step_functions_role_arn: "arn:aws:iam::..."

  # Glue jobs
  transformation_glue_job_name: "my-transformation-job"
  curation_glue_job_name: "my-curation-job"

  # Notifications
  data_pipeline_sns_topic_arn: "arn:aws:sns:..."
  alarm_email_addresses:
    - "data-ops@example.com"
```

---

### Serverless API

**File:** `serverless-api.yaml`

A complete serverless API platform with zero infrastructure to manage.

#### Architecture

```
   Clients              Edge             API Layer           Compute            Data
  +--------+     +---------------+     +----------+     +-------------+     +----------+
  |  Web   |---->|  CloudFront   |---->|   API    |---->|   Lambda    |---->| DynamoDB |
  | Mobile |     |     (CDN)     |     | Gateway  |     | Functions   |     | Tables   |
  +--------+     +---------------+     +----------+     +-------------+     +----------+
       |                |                   |                 |                  |
       |          +-----v-----+       +-----v-----+     +-----v-----+     +-----v-----+
       +--------->|    WAF    |       |  Cognito  |     |    SQS    |     | S3 Assets |
                  | Protection|       |   Auth    |     |  Queues   |     |  Bucket   |
                  +-----------+       +-----------+     +-----------+     +-----------+
```

#### Components

| Component | Description |
|-----------|-------------|
| `serverless-api/cognito` | User pool with clients and MFA |
| `serverless-api/apigateway` | REST/HTTP API Gateway |
| `serverless-api/api-domain` | Custom domain with certificate |
| `serverless-api/acm` | SSL/TLS certificates |
| `serverless-api/lambda-api-handler` | Main API handler function |
| `serverless-api/lambda-authorizer` | Custom authorizer (optional) |
| `serverless-api/lambda-async-processor` | Async task processor |
| `serverless-api/dynamodb` | Single-table design tables |
| `serverless-api/sqs` | Task queues and DLQ |
| `serverless-api/s3-assets` | Static assets and uploads |
| `serverless-api/cloudfront` | CDN for assets |
| `serverless-api/waf` | API protection rules |
| `serverless-api/monitoring` | API metrics and alarms |

#### Required Variables

```yaml
vars:
  # Domain
  app_domain_name: "example.com"
  route53_zone_id: "Z1234567890ABC"

  # KMS keys
  dynamodb_kms_key_arn: "arn:aws:kms:..."
  sqs_kms_key_id: "alias/aws/sqs"
  assets_kms_key_id: "arn:aws:kms:..."

  # Lambda
  lambda_powertools_layer_arn: "arn:aws:lambda:us-east-1:017000801446:layer:AWSLambdaPowertoolsPythonV2:51"

  # Logging
  log_bucket_name: "my-log-bucket"
  waf_log_destination_arn: "arn:aws:s3:::my-waf-logs"
```

#### API Types

```yaml
# HTTP API (lower cost, simpler)
vars:
  api_type: "HTTP"

# REST API (more features)
vars:
  api_type: "REST"
```

---

### Batch Processing

**File:** `batch-processing.yaml`

A complete batch processing infrastructure for large-scale data jobs.

#### Architecture

```
   Job Submission          Queuing            Compute              Storage
  +-------------+     +---------------+     +-----------+     +---------------+
  |    S3       |---->|     SQS       |---->|  AWS      |---->|  S3 Output    |
  |   Events    |     | Job Queues    |     |  Batch    |     |   Bucket      |
  +-------------+     +---------------+     +-----------+     +---------------+
        |                    |                   |                   |
  +-----v-----+        +-----v-----+       +-----v-----+       +-----v-----+
  |EventBridge|        |   Step    |       |  Fargate  |       | CloudWatch|
  | Scheduler |        | Functions |       |   Spot    |       |   Logs    |
  +-----------+        +-----------+       +-----------+       +-----------+
```

#### Components

| Component | Description |
|-----------|-------------|
| `batch-processing/vpc` | VPC with VPC endpoints |
| `batch-processing/securitygroups` | Security groups for compute |
| `batch-processing/s3-input` | Input data bucket with triggers |
| `batch-processing/s3-output` | Output data bucket |
| `batch-processing/s3-scripts` | Job scripts and configs |
| `batch-processing/sqs` | Job submission queues |
| `batch-processing/batch-compute-fargate` | Fargate compute environment |
| `batch-processing/batch-compute-fargate-spot` | Spot compute (cost-optimized) |
| `batch-processing/batch-compute-ec2` | EC2 compute (for GPU) |
| `batch-processing/batch-job-queues` | Priority-based job queues |
| `batch-processing/batch-job-definitions` | Container job definitions |
| `batch-processing/step-functions` | Workflow orchestration |
| `batch-processing/eventbridge` | Scheduling and triggers |
| `batch-processing/monitoring` | Job monitoring and alerts |

#### Required Variables

```yaml
vars:
  # IAM roles
  batch_service_role_arn: "arn:aws:iam::..."
  batch_job_role_arn: "arn:aws:iam::..."
  batch_execution_role_arn: "arn:aws:iam::..."
  eventbridge_step_functions_role_arn: "arn:aws:iam::..."

  # Container images
  data_processor_image: "123456789.dkr.ecr.us-east-1.amazonaws.com/processor:latest"
  etl_job_image: "123456789.dkr.ecr.us-east-1.amazonaws.com/etl:latest"
  report_generator_image: "123456789.dkr.ecr.us-east-1.amazonaws.com/reporter:latest"

  # Supporting Lambdas
  validation_lambda_arn: "arn:aws:lambda:..."
  list_files_lambda_arn: "arn:aws:lambda:..."
  aggregate_lambda_arn: "arn:aws:lambda:..."

  # Notifications
  batch_sns_topic_arn: "arn:aws:sns:..."
```

---

## Best Practices

### 1. Start with Development

Always deploy to development first:

```bash
# Deploy dev
atmos terraform apply web-application/vpc -s myorg-dev-dev

# Test thoroughly, then staging
atmos terraform apply web-application/vpc -s myorg-staging-staging

# Finally production
atmos terraform apply web-application/vpc -s myorg-prod-production
```

### 2. Use Environment-Specific Overrides

Create environment-specific stack files:

```yaml
# stacks/orgs/myorg/dev/web-app.yaml
import:
  - catalog/templates/web-application
  - mixins/development

vars:
  db_instance_class: "db.t3.micro"
  desired_count: 1
```

### 3. Secure Secrets

Never put secrets in stack files:

```yaml
# Good - reference secrets manager
vars:
  database_password_secret_arn: "arn:aws:secretsmanager:..."

# Bad - hardcoded password
vars:
  database_password: "my-secret-password"  # NEVER DO THIS
```

### 4. Enable Monitoring from Day 1

All templates include monitoring components - enable them:

```yaml
vars:
  alarm_email_addresses:
    - "ops@example.com"
    - "oncall@example.com"
  enable_cost_monitoring: true
```

### 5. Use Tagging for Cost Allocation

Add cost allocation tags:

```yaml
vars:
  tags:
    Project: "my-project"
    CostCenter: "engineering"
    Team: "platform"
```

---

## Troubleshooting

### Common Issues

**1. IAM Permission Errors**

Ensure all required IAM roles exist before deploying:

```bash
# Check role exists
aws iam get-role --role-name ecsTaskExecutionRole
```

**2. VPC Endpoint Issues**

If Lambda or ECS can't reach AWS services, check VPC endpoints:

```yaml
vars:
  enable_vpc_endpoints: true
  vpc_endpoints:
    - s3
    - ecr.api
    - ecr.dkr
    - logs
```

**3. Certificate Validation Stuck**

Ensure Route53 zone is correctly configured and DNS propagated:

```bash
# Check DNS
dig +short _acm-challenge.example.com TXT
```

**4. Batch Jobs Not Running**

Check compute environment and job queue status:

```bash
aws batch describe-compute-environments
aws batch describe-job-queues
```

---

## Contributing

To add a new template:

1. Create the YAML file in this directory
2. Follow the existing naming conventions
3. Include comprehensive comments and documentation
4. Add environment-specific override examples
5. List all required variables
6. Update this README

---

## Support

For questions or issues:
- Check the component documentation in `components/terraform/*/README.md`
- Review the Atmos documentation at https://atmos.tools
- Contact the Platform Team
