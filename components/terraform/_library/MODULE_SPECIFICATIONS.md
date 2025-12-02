# Alexandria Library - Module Specifications

This document provides detailed specifications for all 50+ modules in the Alexandria Library.

## Module Implementation Priority

### Priority 1: Foundation Modules (Already Completed or In Progress)
1. ✅ **vpc-advanced** - COMPLETE
2. 🚧 **s3-bucket** - In Progress
3. 🚧 **kms-key** - Planned
4. 🚧 **secrets-manager** - Planned
5. 🚧 **iam-roles-factory** - Planned

### Priority 2: Compute & Database (Most Requested)
6. **eks-blueprint** - Full EKS with addons
7. **rds-postgres** - PostgreSQL with all features
8. **lambda-function** - Lambda with layers, VPC, etc.
9. **dynamodb-table** - DynamoDB with streams, backups
10. **ecs-fargate-service** - Fargate service with ALB

### Priority 3: Integration & Messaging
11. **sqs-queue** - SQS with DLQ and alarms
12. **sns-topic** - SNS with subscriptions
13. **api-gateway-rest** - REST API with auth
14. **kinesis-stream** - Streaming data platform

### Priority 4: Observability & Security
15. **cloudwatch-alarms** - Alarm factory
16. **cloudwatch-dashboard** - Dashboard builder
17. **security-baseline** - Account-level security
18. **waf-rulesets** - WAF rules library

---

## Detailed Module Specifications

### 1. NETWORKING MODULES

#### vpc-advanced ✅ COMPLETE
**Status**: Production Ready
**Location**: `/networking/vpc-advanced/`

**Features**:
- Multi-AZ deployment (2-6 AZs)
- Public, private, database subnet tiers
- NAT Gateway (single or per-AZ)
- Internet Gateway
- VPC Flow Logs (CloudWatch or S3)
- VPN Gateway support
- Transit Gateway attachment
- VPC Endpoints (Gateway & Interface)
- IPv6 support
- DHCP options set
- Default security group management

**Key Resources**:
- aws_vpc
- aws_subnet (public, private, database)
- aws_nat_gateway
- aws_internet_gateway
- aws_flow_log
- aws_vpc_endpoint
- aws_ec2_transit_gateway_vpc_attachment

---

#### vpc-peering
**Status**: Planned
**Priority**: P2

**Features**:
- Bidirectional VPC peering
- Automatic route table updates
- Cross-account peering support
- Cross-region peering support
- DNS resolution configuration
- Multiple peering connections per VPC
- Tags and naming conventions

**Key Resources**:
- aws_vpc_peering_connection
- aws_vpc_peering_connection_accepter
- aws_vpc_peering_connection_options
- aws_route (peering routes)

**Variables**:
```hcl
variable "requester_vpc_id" {}
variable "accepter_vpc_id" {}
variable "accepter_account_id" {}
variable "auto_accept" { default = true }
variable "enable_dns_resolution" { default = true }
```

---

#### transit-gateway
**Status**: Planned
**Priority**: P2

**Features**:
- Multi-VPC connectivity hub
- Multiple route table support
- VPN attachment support
- Direct Connect Gateway attachment
- Appliance mode support
- Auto-accept shared attachments
- Default route table association
- Multicast support (optional)

**Key Resources**:
- aws_ec2_transit_gateway
- aws_ec2_transit_gateway_vpc_attachment
- aws_ec2_transit_gateway_route_table
- aws_ec2_transit_gateway_route
- aws_ec2_transit_gateway_route_table_association

---

#### vpc-endpoints
**Status**: Planned
**Priority**: P3

**Features**:
- Centralized VPC endpoint management
- Gateway endpoints (S3, DynamoDB)
- Interface endpoints for all AWS services
- Private DNS configuration
- Security group attachment
- Subnet placement strategy
- Endpoint policies
- Cost optimization recommendations

**Supported Services**:
- S3, DynamoDB (Gateway)
- EC2, ECR, ECS, Lambda (Interface)
- Systems Manager, Secrets Manager
- CloudWatch Logs, KMS
- RDS, SNS, SQS

---

#### network-firewall
**Status**: Planned
**Priority**: P3

**Features**:
- Stateful rule groups
- Stateless rule groups
- Domain list filtering
- Suricata compatible rules
- TLS inspection (optional)
- Logging to S3/CloudWatch/Kinesis
- Multi-AZ deployment
- Firewall policies

**Key Resources**:
- aws_networkfirewall_firewall
- aws_networkfirewall_firewall_policy
- aws_networkfirewall_rule_group
- aws_networkfirewall_logging_configuration

---

### 2. COMPUTE MODULES

#### eks-blueprint
**Status**: In Progress
**Priority**: P1

**Features**:
- Managed node groups (on-demand, spot)
- Fargate profiles
- IRSA (IAM Roles for Service Accounts)
- Cluster autoscaler
- AWS Load Balancer Controller
- EBS CSI Driver
- EFS CSI Driver
- CoreDNS, kube-proxy, vpc-cni addons
- Pod security policies
- Network policies
- Secrets encryption with KMS
- CloudWatch Container Insights
- Private cluster option
- Cluster authentication via IAM

**Key Resources**:
- aws_eks_cluster
- aws_eks_node_group
- aws_eks_fargate_profile
- aws_eks_addon
- aws_iam_role (cluster, node, pod)
- aws_security_group
- aws_launch_template (for node groups)

**Variables**:
```hcl
variable "cluster_version" { default = "1.28" }
variable "enable_irsa" { default = true }
variable "node_groups" {
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size      = number
    capacity_type  = string  # ON_DEMAND or SPOT
  }))
}
variable "fargate_profiles" { type = map(any) }
variable "addons" {
  type = map(object({
    version              = string
    resolve_conflicts    = string
    service_account_role_arn = string
  }))
}
```

---

#### lambda-function
**Status**: Planned
**Priority**: P1

**Features**:
- Multiple runtime support (Python, Node.js, Go, etc.)
- VPC configuration
- Environment variables (encrypted)
- Lambda layers attachment
- Dead letter queue (DLQ)
- Reserved concurrent executions
- Provisioned concurrency
- Function URL (optional)
- CloudWatch Logs retention
- X-Ray tracing
- Event source mappings (SQS, Kinesis, DynamoDB)
- Deployment package from S3 or local file
- Code signing configuration
- EFS mount support

**Key Resources**:
- aws_lambda_function
- aws_lambda_permission
- aws_lambda_event_source_mapping
- aws_lambda_function_url
- aws_iam_role (execution role)
- aws_cloudwatch_log_group
- aws_lambda_layer_version

**Variables**:
```hcl
variable "runtime" {}
variable "handler" {}
variable "source_code_path" {}
variable "memory_size" { default = 128 }
variable "timeout" { default = 3 }
variable "enable_vpc" { default = false }
variable "vpc_subnet_ids" { default = [] }
variable "vpc_security_group_ids" { default = [] }
variable "environment_variables" { type = map(string), default = {} }
variable "layers" { type = list(string), default = [] }
variable "enable_xray" { default = true }
```

---

#### ecs-fargate-service
**Status**: Planned
**Priority**: P2

**Features**:
- Fargate launch type
- Application Load Balancer integration
- Auto-scaling (CPU, memory, requests)
- Service discovery (Cloud Map)
- Task definition with multiple containers
- Container health checks
- Secrets management (Secrets Manager, SSM)
- CloudWatch Logs
- EFS volume support
- Task IAM role
- Service connect
- Deployment circuit breaker
- Blue/green deployments

**Key Resources**:
- aws_ecs_cluster
- aws_ecs_service
- aws_ecs_task_definition
- aws_lb_target_group
- aws_lb_listener_rule
- aws_appautoscaling_target
- aws_appautoscaling_policy
- aws_service_discovery_service

---

### 3. DATA LAYER MODULES

#### s3-bucket
**Status**: In Progress
**Priority**: P1

**Features**:
- Server-side encryption (SSE-S3, SSE-KMS, DSSE-KMS)
- Versioning with MFA delete
- Lifecycle policies (transitions, expiration)
- Cross-region replication
- Same-region replication
- Bucket logging
- Public access block
- Bucket policies
- CORS configuration
- Website hosting
- Object lock (compliance, governance)
- Intelligent-Tiering
- Event notifications (SNS, SQS, Lambda)
- Request metrics
- Inventory configuration
- Analytics configuration

**Key Resources**:
- aws_s3_bucket
- aws_s3_bucket_versioning
- aws_s3_bucket_server_side_encryption_configuration
- aws_s3_bucket_lifecycle_configuration
- aws_s3_bucket_replication_configuration
- aws_s3_bucket_logging
- aws_s3_bucket_public_access_block
- aws_s3_bucket_policy
- aws_s3_bucket_cors_configuration
- aws_s3_bucket_website_configuration
- aws_s3_bucket_object_lock_configuration
- aws_s3_bucket_notification

**Variables**:
```hcl
variable "bucket_name" {}
variable "enable_versioning" { default = true }
variable "enable_encryption" { default = true }
variable "encryption_type" { default = "sse-s3" }
variable "kms_key_id" { default = null }
variable "lifecycle_rules" { type = list(any), default = [] }
variable "enable_replication" { default = false }
variable "replication_destination_bucket" { default = null }
variable "enable_website" { default = false }
variable "block_public_access" { default = true }
```

---

#### rds-postgres
**Status**: Planned
**Priority**: P1

**Features**:
- PostgreSQL engine (multiple versions)
- Multi-AZ deployment
- Read replicas (multiple regions)
- Automated backups with retention
- Snapshot management
- Encryption at rest (KMS)
- Encryption in transit (SSL/TLS)
- Enhanced monitoring
- Performance Insights
- Parameter groups
- Option groups
- Subnet groups
- Security groups
- IAM database authentication
- CloudWatch alarms (CPU, memory, storage, connections)
- Maintenance window configuration
- Backup window configuration
- Deletion protection
- Auto minor version upgrade

**Key Resources**:
- aws_db_instance
- aws_db_subnet_group
- aws_db_parameter_group
- aws_db_option_group
- aws_security_group
- aws_cloudwatch_metric_alarm
- aws_db_instance_role_association

**Variables**:
```hcl
variable "engine_version" { default = "15.4" }
variable "instance_class" {}
variable "allocated_storage" {}
variable "storage_type" { default = "gp3" }
variable "multi_az" { default = true }
variable "database_name" {}
variable "master_username" {}
variable "enable_enhanced_monitoring" { default = true }
variable "enable_performance_insights" { default = true }
variable "backup_retention_period" { default = 7 }
variable "enable_deletion_protection" { default = true }
```

---

#### dynamodb-table
**Status**: Planned
**Priority**: P1

**Features**:
- On-demand or provisioned billing
- Global tables (multi-region)
- DynamoDB Streams
- Point-in-time recovery (PITR)
- Server-side encryption (AWS owned, AWS managed, or customer managed KMS)
- Global secondary indexes (GSI)
- Local secondary indexes (LSI)
- TTL (Time To Live)
- Auto-scaling (for provisioned capacity)
- CloudWatch alarms
- Contributor Insights
- Table class (Standard, Standard-IA)
- Import from S3
- Export to S3
- Backup and restore

**Key Resources**:
- aws_dynamodb_table
- aws_dynamodb_table_replica (for global tables)
- aws_appautoscaling_target
- aws_appautoscaling_policy
- aws_cloudwatch_metric_alarm

**Variables**:
```hcl
variable "table_name" {}
variable "billing_mode" { default = "PAY_PER_REQUEST" }
variable "hash_key" {}
variable "range_key" { default = null }
variable "attributes" { type = list(object({ name = string, type = string })) }
variable "global_secondary_indexes" { type = list(any), default = [] }
variable "local_secondary_indexes" { type = list(any), default = [] }
variable "enable_streams" { default = false }
variable "stream_view_type" { default = "NEW_AND_OLD_IMAGES" }
variable "enable_pitr" { default = true }
variable "enable_encryption" { default = true }
variable "kms_key_arn" { default = null }
variable "ttl_enabled" { default = false }
variable "ttl_attribute_name" { default = "ttl" }
```

---

#### rds-aurora
**Status**: Planned
**Priority**: P2

**Features**:
- Aurora PostgreSQL or MySQL
- Serverless v2 support
- Global database (multi-region)
- Multiple reader instances
- Auto-scaling reader instances
- Automated backups
- Cluster parameter groups
- DB parameter groups
- Enhanced monitoring
- Performance Insights
- IAM database authentication
- Secrets Manager integration
- CloudWatch alarms
- Backtrack (MySQL only)
- Blue/green deployments

**Key Resources**:
- aws_rds_cluster
- aws_rds_cluster_instance
- aws_rds_cluster_parameter_group
- aws_db_parameter_group
- aws_rds_global_cluster
- aws_appautoscaling_target
- aws_appautoscaling_policy

---

#### elasticache-redis
**Status**: Planned
**Priority**: P2

**Features**:
- Redis engine (6.x, 7.x)
- Cluster mode enabled/disabled
- Multi-AZ with automatic failover
- Read replicas
- Encryption at rest
- Encryption in transit (TLS)
- Auth token support
- Automatic backups
- Snapshot management
- Parameter groups
- Subnet groups
- Security groups
- CloudWatch metrics and alarms
- Slow log to CloudWatch
- Maintenance window
- Notification SNS topic

**Key Resources**:
- aws_elasticache_replication_group
- aws_elasticache_cluster
- aws_elasticache_parameter_group
- aws_elasticache_subnet_group
- aws_security_group
- aws_cloudwatch_metric_alarm

---

### 4. INTEGRATION MODULES

#### sqs-queue
**Status**: Planned
**Priority**: P1

**Features**:
- Standard or FIFO queue
- Dead letter queue (DLQ)
- Message retention (1-14 days)
- Visibility timeout configuration
- Server-side encryption (SSE-SQS or SSE-KMS)
- Queue policies
- CloudWatch alarms (age, depth, DLQ messages)
- Redrive policy
- Content-based deduplication (FIFO)
- High throughput mode (FIFO)
- Delay seconds
- Max message size
- Receive wait time (long polling)

**Key Resources**:
- aws_sqs_queue
- aws_sqs_queue_policy
- aws_cloudwatch_metric_alarm

**Variables**:
```hcl
variable "queue_name" {}
variable "fifo_queue" { default = false }
variable "enable_dlq" { default = true }
variable "max_receive_count" { default = 3 }
variable "message_retention_seconds" { default = 345600 }  # 4 days
variable "visibility_timeout_seconds" { default = 30 }
variable "enable_encryption" { default = true }
variable "kms_key_id" { default = null }
variable "delay_seconds" { default = 0 }
variable "receive_wait_time_seconds" { default = 0 }
```

**Outputs**:
```hcl
output "queue_id" {}
output "queue_arn" {}
output "queue_url" {}
output "dlq_id" {}
output "dlq_arn" {}
output "dlq_url" {}
```

---

#### sns-topic
**Status**: Planned
**Priority**: P2

**Features**:
- Standard or FIFO topic
- Server-side encryption (KMS)
- Subscriptions (Email, SMS, SQS, Lambda, HTTP/S)
- Topic policies
- Delivery status logging
- Message filtering
- Dead letter queue for subscriptions
- Subscription filter policies
- Message attributes
- Message deduplication (FIFO)
- CloudWatch alarms

**Key Resources**:
- aws_sns_topic
- aws_sns_topic_subscription
- aws_sns_topic_policy
- aws_cloudwatch_metric_alarm

---

#### api-gateway-rest
**Status**: Planned
**Priority**: P2

**Features**:
- REST API with resources and methods
- Lambda integration
- HTTP integration
- AWS service integration
- Request/response transformations
- API Gateway authorizers (Lambda, Cognito, IAM)
- API keys and usage plans
- Throttling and quota limits
- Stage variables
- Deployment stages (dev, staging, prod)
- Custom domain names
- WAF association
- Access logging to CloudWatch
- X-Ray tracing
- CORS configuration
- Request validators
- Models and schemas

**Key Resources**:
- aws_api_gateway_rest_api
- aws_api_gateway_resource
- aws_api_gateway_method
- aws_api_gateway_integration
- aws_api_gateway_deployment
- aws_api_gateway_stage
- aws_api_gateway_authorizer
- aws_api_gateway_api_key
- aws_api_gateway_usage_plan
- aws_api_gateway_domain_name
- aws_api_gateway_base_path_mapping

---

#### kinesis-stream
**Status**: Planned
**Priority**: P2

**Features**:
- On-demand or provisioned capacity
- Enhanced fan-out
- Server-side encryption (KMS)
- Data retention (1-365 days)
- Shard management
- CloudWatch metrics
- Stream consumers
- Firehose integration
- Lambda integration

**Key Resources**:
- aws_kinesis_stream
- aws_kinesis_stream_consumer
- aws_cloudwatch_metric_alarm

---

### 5. SECURITY MODULES

#### kms-key
**Status**: Planned
**Priority**: P1

**Features**:
- Symmetric or asymmetric keys
- Multi-region keys
- Key rotation (automatic annual rotation)
- Key policies with least privilege
- Key aliases
- Grants for temporary access
- CloudWatch alarms for key usage
- Cost allocation tags
- Key deletion with pending window
- Key administrators and users separation

**Key Resources**:
- aws_kms_key
- aws_kms_alias
- aws_kms_grant
- aws_kms_replica_key (for multi-region)
- aws_cloudwatch_metric_alarm

**Variables**:
```hcl
variable "description" {}
variable "enable_key_rotation" { default = true }
variable "deletion_window_in_days" { default = 30 }
variable "key_administrators" { type = list(string) }
variable "key_users" { type = list(string) }
variable "key_service_users" { type = list(string), default = [] }
variable "alias_name" {}
variable "multi_region" { default = false }
```

---

#### secrets-manager
**Status**: Planned
**Priority**: P1

**Features**:
- Secret storage with encryption
- Automatic rotation (Lambda-based)
- Version management
- Resource policies
- Replica secrets (multi-region)
- CloudWatch alarms for access
- Recovery window on deletion
- Tags for organization
- Integration with RDS, Redshift, DocumentDB

**Key Resources**:
- aws_secretsmanager_secret
- aws_secretsmanager_secret_version
- aws_secretsmanager_secret_rotation
- aws_secretsmanager_secret_policy
- aws_lambda_function (for rotation)
- aws_secretsmanager_secret_replica

**Variables**:
```hcl
variable "secret_name" {}
variable "description" {}
variable "secret_string" { sensitive = true }
variable "kms_key_id" {}
variable "enable_rotation" { default = false }
variable "rotation_lambda_arn" { default = null }
variable "rotation_days" { default = 30 }
variable "recovery_window_days" { default = 30 }
variable "replica_regions" { type = list(string), default = [] }
```

---

#### security-baseline
**Status**: Planned
**Priority**: P3

**Features**:
- AWS Config enabled in all regions
- CloudTrail with multi-region trail
- GuardDuty enabled
- Security Hub with standards enabled
- IAM password policy
- IAM access analyzer
- S3 public access block (account-level)
- EBS encryption by default
- VPC Flow Logs for default VPCs
- SNS topic for security alerts
- CloudWatch Logs for centralized logging
- AWS Config rules for compliance
- EventBridge rules for security events

**Key Resources**:
- aws_config_configuration_recorder
- aws_config_delivery_channel
- aws_config_configuration_recorder_status
- aws_cloudtrail
- aws_guardduty_detector
- aws_securityhub_account
- aws_securityhub_standards_subscription
- aws_iam_account_password_policy
- aws_accessanalyzer_analyzer
- aws_s3_account_public_access_block
- aws_ebs_encryption_by_default

---

### 6. OBSERVABILITY MODULES

#### cloudwatch-alarms
**Status**: Planned
**Priority**: P2

**Features**:
- Alarm factory pattern
- Pre-built alarm sets (EC2, RDS, Lambda, ECS, ALB, etc.)
- Composite alarms
- SNS topic integration
- Alarm actions (auto-scaling, Lambda, Systems Manager)
- Metric math support
- Anomaly detection
- Cross-account alarms
- Alarm templates by resource type

**Key Resources**:
- aws_cloudwatch_metric_alarm
- aws_cloudwatch_composite_alarm
- aws_sns_topic
- aws_sns_topic_subscription

**Alarm Types**:
- EC2: CPU, disk, memory (via CloudWatch agent), status checks
- RDS: CPU, memory, storage, connections, replica lag
- Lambda: errors, throttles, duration, concurrent executions
- ECS: CPU, memory, task count
- ALB: target response time, unhealthy hosts, 5xx errors
- API Gateway: latency, 4xx, 5xx, count
- SQS: age of oldest message, queue depth, DLQ messages
- DynamoDB: read/write throttles, consumed capacity

---

#### cloudwatch-dashboard
**Status**: Planned
**Priority**: P2

**Features**:
- Dashboard builder from configuration
- Pre-built dashboard templates
- Widget types (metric, log, number, text, alarm status)
- Multi-region dashboards
- Cross-account dashboards
- Metric math widgets
- Log insights queries
- Custom periods and statistics
- Auto-refresh
- Dark/light theme support

**Key Resources**:
- aws_cloudwatch_dashboard

---

### 7. APPLICATION PATTERN MODULES

#### serverless-api
**Status**: Planned
**Priority**: P3

**Full Stack Pattern**:
- API Gateway (REST or HTTP API)
- Lambda functions (multiple endpoints)
- DynamoDB table
- Cognito User Pool (authentication)
- S3 bucket (file storage)
- CloudFront distribution (optional)
- CloudWatch Logs and alarms
- X-Ray tracing
- VPC integration (optional)

**Resources Created**:
- Complete API with CRUD operations
- Database with indexes
- Authentication and authorization
- Storage with presigned URLs
- CDN for static assets
- Monitoring and alerting
- CI/CD pipeline configuration

---

#### microservices-platform
**Status**: Planned
**Priority**: P3

**Full Stack Pattern**:
- EKS cluster with managed node groups
- Application Load Balancer
- AWS Load Balancer Controller
- External DNS
- Cert Manager
- Cluster Autoscaler
- Metrics Server
- Prometheus + Grafana
- Fluentd for logging
- Service Mesh (optional: Istio/App Mesh)
- Container registry (ECR)
- CI/CD with CodePipeline/GitLab/GitHub Actions
- Secrets management (External Secrets Operator)

---

#### data-lake
**Status**: Planned
**Priority**: P3

**Full Stack Pattern**:
- S3 buckets (raw, processed, curated)
- AWS Glue Data Catalog
- AWS Glue Crawlers
- AWS Glue ETL jobs
- Athena workgroups
- Lake Formation permissions
- QuickSight dashboards (optional)
- Step Functions for orchestration
- Lambda for data transformations
- EventBridge for scheduling
- CloudWatch monitoring

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- ✅ vpc-advanced
- 🚧 s3-bucket
- 🚧 kms-key
- 🚧 secrets-manager
- sqs-queue

### Phase 2: Compute & Database (Weeks 3-4)
- eks-blueprint
- lambda-function
- rds-postgres
- dynamodb-table
- ecs-fargate-service

### Phase 3: Integration (Week 5)
- sns-topic
- api-gateway-rest
- kinesis-stream
- elasticache-redis

### Phase 4: Observability & Security (Week 6)
- cloudwatch-alarms
- cloudwatch-dashboard
- security-baseline
- waf-rulesets

### Phase 5: Advanced Networking (Week 7)
- vpc-peering
- transit-gateway
- vpc-endpoints
- network-firewall

### Phase 6: Application Patterns (Week 8)
- serverless-api
- microservices-platform
- data-lake
- three-tier-web-app

### Phase 7: Remaining Modules (Weeks 9-10)
- All remaining modules from each category
- Documentation updates
- Testing and validation
- Examples and tutorials

---

## Module Quality Checklist

Each module must have:
- [ ] Complete README with examples
- [ ] All required .tf files (main, variables, outputs, versions)
- [ ] At least 2 working examples (simple, complete)
- [ ] CHANGELOG.md
- [ ] Input validation
- [ ] Comprehensive outputs
- [ ] Security best practices
- [ ] Cost optimization notes
- [ ] Known issues documented
- [ ] Tags on all resources

---

## Support and Maintenance

- Module versions follow SemVer
- Breaking changes increment MAJOR version
- New features increment MINOR version
- Bug fixes increment PATCH version
- All changes documented in CHANGELOG.md
- Security updates have priority
- AWS provider version updates tested before release
