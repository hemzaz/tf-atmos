# Terraform Module Library

Production-ready Terraform modules organized by category.

## Categories

- **cicd/** - CodePipeline, CodeBuild, ECR, CodeDeploy
- **compute/** - ECS Fargate, Lambda patterns, Auto-scaling
- **data-layer/** - Aurora RDS, DynamoDB, ElastiCache, S3
- **data-platform/** - Glue, Athena, EMR, data processing
- **integration/** - SQS, SNS, EventBridge, Step Functions, API Gateway
- **networking/** - VPC with advanced features
- **observability/** - CloudWatch, X-Ray, monitoring
- **security/** - WAF, KMS, Secrets Manager
- **storage/** - EFS, FSx Lustre, Backup Vault, S3 Replication

## Usage

Each module includes:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `README.md` - Module documentation

See individual module READMEs for usage examples.

## Module Registry

See `../_catalog/module-registry.yaml` for complete module catalog.
