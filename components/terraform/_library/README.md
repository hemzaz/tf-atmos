# Terraform module library

Reusable Terraform modules, grouped by category. Components consume them with a
relative `source = "../_library/<category>/<module>"` (some `cicd/*` modules are
versioned: `source = "../_library/cicd/<module>/v1.0.0"`). Each module directory
has its own `main.tf`/`variables.tf`/`outputs.tf`; several also ship an `examples/`
dir that only exercises that module (self-referencing, not a real consumer).

Only one module is actually wired into a component today: `kms` uses
`security/kms-multi-region`. Everything else has no `source = "../_library/..."`
reference anywhere under `components/terraform/`.

`../_catalog/module-registry.yaml` carries per-module metadata (versions, cost
estimates, maturity, maintainers) for all modules below, but nothing in this repo
reads it — no script or CLI consumes it. Treat it as unmaintained reference data,
not a live registry.

| Module | Purpose | Used by |
|---|---|---|
| `cicd/codebuild-project` | CodeBuild project + IAM role + log group + webhook | unused |
| `cicd/codedeploy-app` | CodeDeploy app, deployment group and config, IAM role | unused |
| `cicd/codepipeline` | CodePipeline + EventBridge trigger rule + IAM role | unused |
| `cicd/ecr-repository` | ECR repo: lifecycle policy, replication, pull-through cache, scanning | unused |
| `compute/asg-launch-template` | Auto Scaling group + launch template, scaling policies/schedules, alarms | unused |
| `compute/ecs-fargate-service` | ECS Fargate service, autoscaling, CodeDeploy blue/green, log group | unused |
| `compute/lambda-pattern-library` | Lambda function with common event-source/IAM/log-group wiring | unused |
| `data-layer/dynamodb-advanced` | DynamoDB table with autoscaling policies | unused |
| `data-layer/elasticache-redis` | ElastiCache Redis replication group, subnet/parameter groups, alarms | unused |
| `data-layer/rds-aurora-advanced` | Aurora cluster, autoscaling, parameter/subnet groups, alarms | unused |
| `data-layer/s3-bucket` | S3 bucket module | unused |
| `data-platform/athena-workgroup` | Athena workgroup, data catalog, named queries, alarms | unused |
| `data-platform/glue-catalog` | Glue database/tables/crawler/registry, data-quality rulesets, alarms | unused |
| `data-platform/kinesis-firehose` | Kinesis Firehose delivery stream (S3 dest), IAM role, alarms | unused |
| `data-platform/kinesis-stream` | Kinesis data stream + consumer + autoscaling + alarms | unused |
| `data-platform/opensearch` | OpenSearch domain, service-linked role, log resource policy, alarms | unused |
| `integration/api-gateway-rest` | API Gateway REST API: deployment, domain mapping, API keys, method settings | unused |
| `integration/eventbridge-bus` | EventBridge bus, rules/targets, archive, bus policy, alarms | unused |
| `integration/sns-topic` | SNS topic with KMS key, access policy, alarms | unused |
| `integration/sqs-queue` | SQS queue with KMS key, queue policy, alarms | unused |
| `integration/step-functions` | Step Functions state machine, IAM role, log group, alarms | unused |
| `networking/nat-gateway-ha` | Per-AZ NAT gateways + EIPs + route tables, dashboard, alarms | unused |
| `networking/network-firewall` | AWS Network Firewall: policy, rule groups, logging | unused |
| `networking/transit-gateway` | VPN/customer gateway + RAM share for cross-account TGW attachment | unused |
| `networking/vpc-advanced` | VPC with flow logs, DB subnet group, default SG lockdown, EIPs | unused |
| `networking/vpc-endpoints` | VPC interface/gateway endpoints + security group | unused |
| `networking/vpn-connection` | Site-to-site VPN: customer/VPN gateway, connection, routes, alarms | unused |
| `observability/cloudwatch-alarms` | Composite + metric alarms, SNS topic, Lambda alarm-action handler | unused |
| `observability/cloudwatch-dashboard` | CloudWatch dashboard + log metric filters | unused |
| `observability/log-aggregation` | Central log group, Athena database/workgroup for log queries, event routing | unused |
| `observability/xray-tracing` | X-Ray sampling rules/groups, API Gateway/Lambda tracing config, alarms | unused |
| `security/kms-multi-region` | Multi-region KMS key + replica + alias + grants | **`kms` component** |
| `security/secrets-manager-advanced` | Secrets Manager rotation Lambda + IAM role + rotation config | unused |
| `security/waf-advanced` | WAF Web ACL + logging | unused |
| `storage/backup-vault` | AWS Backup vault, plan, selection, lock config, notifications | unused |
| `storage/efs-filesystem` | EFS file system, access points, mount targets, backup policy, alarms | unused |
| `storage/fsx-lustre` | FSx for Lustre file system + data repository association + KMS key | unused |
| `storage/s3-replication` | S3 cross-region/account replication IAM role + policy, alarms | unused |
