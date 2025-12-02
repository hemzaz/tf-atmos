# API Reference - Complete Component Catalog

**The Definitive Reference for All Alexandria Library Components**

This document provides a complete API reference for all 24 components in the Alexandria Library. Use this as your comprehensive lookup guide for inputs, outputs, dependencies, and usage examples.

---

## Table of Contents

- [Foundations](#foundations)
  - [backend](#backend)
  - [vpc](#vpc)
  - [iam](#iam)
  - [securitygroup](#securitygroup)
- [Compute](#compute)
  - [eks](#eks)
  - [eks-addons](#eks-addons)
  - [eks-backend-services](#eks-backend-services)
  - [ecs](#ecs)
  - [ec2](#ec2)
  - [lambda](#lambda)
- [Data](#data)
  - [rds](#rds)
  - [secretsmanager](#secretsmanager)
  - [backup](#backup)
- [Integration](#integration)
  - [apigateway](#apigateway)
  - [external-secrets](#external-secrets)
  - [dns](#dns)
- [Observability](#observability)
  - [monitoring](#monitoring)
  - [security-monitoring](#security-monitoring)
  - [cost-monitoring](#cost-monitoring)
- [Security](#security)
  - [acm](#acm)
  - [idp-platform](#idp-platform)
  - [cost-optimization](#cost-optimization)

---

## Foundations

### backend

**Purpose**: Terraform state storage and locking infrastructure

**Category**: Foundations
**Maturity**: ✅ Production
**Cost Impact**: $ Low ($5-50/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | Name prefix for backend resources |
| `region` | string | - | Yes | AWS region |
| `enable_versioning` | bool | `true` | No | Enable S3 versioning |
| `enable_replication` | bool | `false` | No | Enable cross-region replication |
| `replication_region` | string | `null` | No | Replication destination region |
| `enable_backup` | bool | `true` | No | Enable backup configuration |
| `lifecycle_rules` | list(object) | `[]` | No | S3 lifecycle rules |
| `dynamodb_billing_mode` | string | `"PAY_PER_REQUEST"` | No | DynamoDB billing mode |
| `tags` | map(string) | `{}` | No | Additional tags |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `s3_bucket_id` | string | State bucket ID |
| `s3_bucket_arn` | string | State bucket ARN |
| `dynamodb_table_id` | string | Lock table ID |
| `dynamodb_table_arn` | string | Lock table ARN |
| `kms_key_id` | string | Encryption key ID |
| `backup_bucket_id` | string | Backup bucket ID (if enabled) |

#### Dependencies

- None (first component to deploy)

#### Related Components

- All components use this for state storage

#### Usage Example

```yaml
components:
  terraform:
    backend:
      vars:
        name: "mycompany-terraform"
        region: "us-east-1"
        enable_versioning: true
        enable_replication: true
        replication_region: "us-west-2"
```

**Documentation**: [components/terraform/backend/README.md](../../components/terraform/backend/README.md)

---

### vpc

**Purpose**: Virtual Private Cloud with networking infrastructure

**Category**: Foundations
**Maturity**: ✅ Production
**Cost Impact**: $$ Medium ($35-135/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `name` | string | - | Yes | VPC name |
| `region` | string | - | Yes | AWS region |
| `vpc_cidr` | string | - | Yes | VPC CIDR block |
| `azs` | list(string) | - | Yes | Availability zones |
| `public_subnets` | list(string) | `[]` | No | Public subnet CIDRs |
| `private_subnets` | list(string) | `[]` | No | Private subnet CIDRs |
| `database_subnets` | list(string) | `[]` | No | Database subnet CIDRs |
| `enable_nat_gateway` | bool | `true` | No | Enable NAT gateways |
| `single_nat_gateway` | bool | `false` | No | Use single NAT gateway |
| `one_nat_gateway_per_az` | bool | `true` | No | One NAT per AZ |
| `enable_vpn_gateway` | bool | `false` | No | Enable VPN gateway |
| `enable_flow_log` | bool | `true` | No | Enable VPC flow logs |
| `enable_endpoints` | bool | `false` | No | Enable VPC endpoints |
| `endpoint_services` | list(string) | `[]` | No | VPC endpoint services |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `vpc_id` | string | VPC ID |
| `vpc_cidr_block` | string | VPC CIDR block |
| `public_subnet_ids` | list(string) | Public subnet IDs |
| `private_subnet_ids` | list(string) | Private subnet IDs |
| `database_subnet_ids` | list(string) | Database subnet IDs |
| `nat_gateway_ids` | list(string) | NAT gateway IDs |
| `igw_id` | string | Internet gateway ID |
| `vpc_endpoint_ids` | map(string) | VPC endpoint IDs |

#### Dependencies

- None (deploys after backend)

#### Related Components

- Required by: eks, ecs, rds, lambda (VPC mode), ec2

#### Usage Example

```yaml
components:
  terraform:
    vpc:
      vars:
        name: "mycompany-prod-vpc"
        region: "us-east-1"
        vpc_cidr: "10.0.0.0/16"
        azs: ["us-east-1a", "us-east-1b", "us-east-1c"]
        public_subnets: ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
        private_subnets: ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
        database_subnets: ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
        enable_nat_gateway: true
        one_nat_gateway_per_az: true
        enable_flow_logs: true
        enable_endpoints: true
        endpoint_services: ["s3", "dynamodb", "ecr.api", "ecr.dkr"]
```

**Documentation**: [components/terraform/vpc/README.md](../../components/terraform/vpc/README.md)

---

### iam

**Purpose**: Identity and access management

**Category**: Foundations
**Maturity**: ✅ Production
**Cost Impact**: Free

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `region` | string | - | Yes | AWS region |
| `create_eks_cluster_role` | bool | `false` | No | Create EKS cluster role |
| `create_eks_node_role` | bool | `false` | No | Create EKS node role |
| `create_ecs_task_execution_role` | bool | `false` | No | Create ECS task execution role |
| `create_lambda_execution_role` | bool | `false` | No | Create Lambda execution role |
| `create_ec2_instance_profile` | bool | `false` | No | Create EC2 instance profile |
| `custom_policies` | map(object) | `{}` | No | Custom IAM policies |
| `cross_account_roles` | map(object) | `{}` | No | Cross-account assume roles |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `eks_cluster_role_arn` | string | EKS cluster role ARN |
| `eks_node_role_arn` | string | EKS node role ARN |
| `ecs_task_execution_role_arn` | string | ECS task execution role ARN |
| `lambda_execution_role_arn` | string | Lambda execution role ARN |
| `ec2_instance_profile_name` | string | EC2 instance profile name |

#### Dependencies

- None

#### Related Components

- Required by: eks, ecs, lambda, ec2

#### Usage Example

```yaml
components:
  terraform:
    iam:
      vars:
        region: "us-east-1"
        create_eks_cluster_role: true
        create_eks_node_role: true
        create_ecs_task_execution_role: true
        custom_policies:
          s3_read:
            actions: ["s3:GetObject", "s3:ListBucket"]
            resources: ["arn:aws:s3:::my-bucket/*"]
```

**Documentation**: [components/terraform/iam/README.md](../../components/terraform/iam/README.md)

---

### securitygroup

**Purpose**: Network firewall rules

**Category**: Foundations
**Maturity**: ✅ Production
**Cost Impact**: Free

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `region` | string | - | Yes | AWS region |
| `vpc_id` | string | - | Yes | VPC ID |
| `security_groups` | map(object) | `{}` | Yes | Security group definitions |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `security_group_ids` | map(string) | Map of security group IDs |

#### Dependencies

- vpc

#### Related Components

- Required by: eks, ecs, rds, ec2

#### Usage Example

```yaml
components:
  terraform:
    securitygroup:
      vars:
        vpc_id: "${vpc.vpc_id}"
        security_groups:
          alb:
            name: "alb-sg"
            ingress_rules:
              - from_port: 443
                to_port: 443
                protocol: "tcp"
                cidr_blocks: ["0.0.0.0/0"]
          app:
            name: "app-sg"
            ingress_rules:
              - from_port: 8080
                to_port: 8080
                protocol: "tcp"
                source_security_group_id: "${securitygroup.alb.id}"
```

**Documentation**: [components/terraform/securitygroup/README.md](../../components/terraform/securitygroup/README.md)

---

## Compute

### eks

**Purpose**: Managed Kubernetes clusters

**Category**: Compute
**Maturity**: ✅ Production
**Cost Impact**: $$$ High ($300-2000+/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `cluster_name` | string | - | Yes | EKS cluster name |
| `cluster_version` | string | `"1.28"` | No | Kubernetes version |
| `vpc_id` | string | - | Yes | VPC ID |
| `subnet_ids` | list(string) | - | Yes | Subnet IDs |
| `node_groups` | map(object) | `{}` | No | Managed node group configurations |
| `fargate_profiles` | map(object) | `{}` | No | Fargate profile configurations |
| `cluster_enabled_log_types` | list(string) | `[]` | No | CloudWatch log types |
| `enable_irsa` | bool | `true` | No | Enable IRSA (OIDC) |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `cluster_id` | string | Cluster ID |
| `cluster_arn` | string | Cluster ARN |
| `cluster_endpoint` | string | Cluster API endpoint |
| `cluster_certificate_authority_data` | string | Cluster CA cert (sensitive) |
| `oidc_provider_arn` | string | OIDC provider ARN |
| `node_group_ids` | list(string) | Node group IDs |

#### Dependencies

- vpc, iam, securitygroup

#### Related Components

- eks-addons (required for production)
- monitoring, backup

**Documentation**: [components/terraform/eks/README.md](../../components/terraform/eks/README.md)

---

### lambda

**Purpose**: Serverless function execution

**Category**: Compute
**Maturity**: ✅ Production
**Cost Impact**: $ Low ($10-100/month typically)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `functions` | map(object) | `{}` | Yes | Function definitions |

**Function object**:
```hcl
{
  function_name         = string
  runtime              = string  # python3.11, nodejs18.x, etc.
  handler              = string
  timeout              = number
  memory_size          = number
  source_dir           = string
  environment_variables = map(string)
  iam_policy_statements = list(object)
  event_sources        = map(object)
  vpc_config           = object (optional)
}
```

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `function_arns` | map(string) | Function ARNs |
| `function_names` | map(string) | Function names |
| `function_invoke_arns` | map(string) | Invoke ARNs |
| `function_role_arns` | map(string) | Execution role ARNs |

#### Dependencies

- Optional: vpc (if VPC mode), iam

#### Related Components

- apigateway, monitoring

**Documentation**: [components/terraform/lambda/README.md](../../components/terraform/lambda/README.md)

---

## Data

### rds

**Purpose**: Relational database services

**Category**: Data
**Maturity**: ✅ Production
**Cost Impact**: $$$ High ($50-1000+/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `identifier` | string | - | Yes | Database identifier |
| `engine` | string | - | Yes | Database engine (postgres, mysql, aurora-postgresql) |
| `engine_version` | string | - | No | Engine version |
| `instance_class` | string | - | Yes | Instance class (db.t3.micro, etc.) |
| `allocated_storage` | number | `20` | No | Storage in GB |
| `storage_type` | string | `"gp3"` | No | Storage type |
| `db_name` | string | - | Yes | Database name |
| `username` | string | - | Yes | Master username |
| `password` | string | - | Yes | Master password (use secrets) |
| `vpc_id` | string | - | Yes | VPC ID |
| `subnet_ids` | list(string) | - | Yes | Subnet IDs |
| `multi_az` | bool | `false` | No | Multi-AZ deployment |
| `backup_retention_period` | number | `7` | No | Backup retention days |
| `enable_encryption` | bool | `true` | No | Enable encryption |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `db_instance_id` | string | Database instance ID |
| `db_instance_arn` | string | Database instance ARN |
| `db_instance_endpoint` | string | Database endpoint |
| `db_instance_address` | string | Database address |
| `db_instance_port` | number | Database port |
| `master_username` | string | Master username |

#### Dependencies

- vpc, securitygroup

#### Related Components

- backup, monitoring, secretsmanager

**Documentation**: [components/terraform/rds/README.md](../../components/terraform/rds/README.md)

---

### secretsmanager

**Purpose**: Secure secret storage

**Category**: Data
**Maturity**: ✅ Production
**Cost Impact**: $ Low ($0.40/secret/month + API calls)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `secrets` | map(object) | `{}` | Yes | Secret definitions |

**Secret object**:
```hcl
{
  name          = string
  description   = string
  secret_string = string (optional)
  recovery_window_in_days = number
}
```

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `secret_arns` | map(string) | Secret ARNs |
| `secret_ids` | map(string) | Secret IDs |

#### Dependencies

- None

#### Related Components

- eks, ecs, lambda, rds

**Documentation**: [components/terraform/secretsmanager/README.md](../../components/terraform/secretsmanager/README.md)

---

### backup

**Purpose**: Automated backup and recovery

**Category**: Data
**Maturity**: ✅ Production
**Cost Impact**: $$ Medium ($10-100/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `backup_vault_name` | string | - | Yes | Backup vault name |
| `backup_plans` | map(object) | `{}` | Yes | Backup plan definitions |
| `backup_selections` | map(object) | `{}` | Yes | Backup selection rules |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `backup_vault_id` | string | Backup vault ID |
| `backup_vault_arn` | string | Backup vault ARN |
| `backup_plan_ids` | map(string) | Backup plan IDs |

#### Dependencies

- None (operates on resource ARNs)

#### Related Components

- rds, efs, dynamodb

**Documentation**: [components/terraform/backup/README.md](../../components/terraform/backup/README.md)

---

## Integration

### apigateway

**Purpose**: API management and routing

**Category**: Integration
**Maturity**: ✅ Production
**Cost Impact**: $$ Medium ($3.50/million requests)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `api_name` | string | - | Yes | API name |
| `api_type` | string | `"http"` | No | API type (http, rest, websocket) |
| `protocol_type` | string | `"HTTP"` | No | Protocol type |
| `routes` | map(object) | `{}` | Yes | Route definitions |
| `cors_configuration` | object | `null` | No | CORS configuration |
| `stage_name` | string | `"$default"` | No | Stage name |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `api_id` | string | API Gateway ID |
| `api_endpoint` | string | API endpoint URL |
| `api_execution_arn` | string | Execution ARN |

#### Dependencies

- Optional: lambda, vpc, acm

#### Related Components

- lambda, monitoring, acm (for custom domains)

**Documentation**: [components/terraform/apigateway/README.md](../../components/terraform/apigateway/README.md)

---

### dns

**Purpose**: Route 53 DNS management

**Category**: Integration
**Maturity**: ✅ Production
**Cost Impact**: $ Low ($0.50/hosted zone/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `domain_name` | string | - | Yes | Domain name |
| `records` | map(object) | `{}` | No | DNS record definitions |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `zone_id` | string | Hosted zone ID |
| `name_servers` | list(string) | Name servers |

**Documentation**: [components/terraform/dns/README.md](../../components/terraform/dns/README.md)

---

## Observability

### monitoring

**Purpose**: CloudWatch dashboards and alarms

**Category**: Observability
**Maturity**: ✅ Production
**Cost Impact**: $ Low ($10-50/month)

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `dashboard_name` | string | - | Yes | Dashboard name |
| `alarm_email` | string | - | No | SNS email for alarms |
| `enable_eks_monitoring` | bool | `false` | No | Enable EKS monitoring |
| `enable_ecs_monitoring` | bool | `false` | No | Enable ECS monitoring |
| `enable_rds_monitoring` | bool | `false` | No | Enable RDS monitoring |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `dashboard_arn` | string | Dashboard ARN |
| `sns_topic_arn` | string | SNS topic ARN |
| `alarm_arns` | list(string) | Alarm ARNs |

**Documentation**: [components/terraform/monitoring/README.md](../../components/terraform/monitoring/README.md)

---

## Security

### acm

**Purpose**: SSL/TLS certificate management

**Category**: Security
**Maturity**: ✅ Production
**Cost Impact**: Free

#### Key Inputs

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `domain_name` | string | - | Yes | Domain name |
| `subject_alternative_names` | list(string) | `[]` | No | Additional SANs |
| `validation_method` | string | `"DNS"` | No | Validation method |

#### Key Outputs

| Output | Type | Description |
|--------|------|-------------|
| `certificate_arn` | string | Certificate ARN |
| `certificate_id` | string | Certificate ID |
| `validation_records` | list(object) | DNS validation records |

**Documentation**: [components/terraform/acm/README.md](../../components/terraform/acm/README.md)

---

## Quick Reference Tables

### By Cost Impact

| Cost Level | Components |
|------------|------------|
| **Free** | iam, securitygroup, acm |
| **$ Low** | backend, secretsmanager, lambda, dns, monitoring, cost-monitoring |
| **$$ Medium** | vpc, ecs, ec2, apigateway, backup, security-monitoring |
| **$$$ High** | eks, eks-addons, rds, cost-optimization |

### By Complexity

| Complexity | Components |
|------------|------------|
| **Low** | backend, iam, securitygroup, lambda, secretsmanager, acm, dns |
| **Medium** | vpc, ecs, ec2, rds, apigateway, monitoring, backup |
| **High** | eks, eks-addons, security-monitoring |

### By Deployment Order

1. **Tier 0**: backend
2. **Tier 1**: vpc, iam
3. **Tier 2**: securitygroup, secretsmanager
4. **Tier 3**: eks/ecs/ec2/lambda, rds, acm, dns
5. **Tier 4**: eks-addons, apigateway, monitoring
6. **Tier 5**: backup, security-monitoring

---

## Usage Patterns

### Pattern: Complete Web Application

```yaml
components:
  terraform:
    # Tier 0-2: Foundations
    backend: { vars: { name: "myapp" } }
    vpc: { vars: { vpc_cidr: "10.0.0.0/16" } }
    iam: { vars: { create_ecs_task_execution_role: true } }
    securitygroup: { vars: { vpc_id: "${vpc.vpc_id}" } }

    # Tier 3: Compute & Data
    ecs: { vars: { cluster_name: "myapp" } }
    rds: { vars: { engine: "postgres" } }
    acm: { vars: { domain_name: "myapp.com" } }

    # Tier 4: Integration & Observability
    apigateway: { vars: { api_name: "myapp-api" } }
    monitoring: { vars: { dashboard_name: "myapp" } }

    # Tier 5: Operations
    backup: { vars: { backup_vault_name: "myapp" } }
```

---

## Version Compatibility

| Component | Terraform | AWS Provider | Atmos |
|-----------|-----------|--------------|-------|
| All | >= 1.9.0 | ~> 5.74.0 | >= 1.163.0 |

---

## Additional Resources

- **[Library Guide](../LIBRARY_GUIDE.md)** - Complete library overview
- **[Search Index](./SEARCH_INDEX.md)** - Searchable component index
- **[Component Categories](./README.md)** - Category documentation
- **[Examples](../../examples/)** - Working examples

---

**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
**Total Components**: 24
