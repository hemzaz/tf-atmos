# Variable Reference Guide

Complete reference for all Terraform component variables in the platform.

## Table of Contents

- [Common Variables](#common-variables)
- [VPC Component](#vpc-component)
- [EKS Component](#eks-component)
- [RDS Component](#rds-component)
- [IAM Component](#iam-component)
- [Monitoring Component](#monitoring-component)
- [Security Group Component](#securitygroup-component)
- [Lambda Component](#lambda-component)
- [API Gateway Component](#apigateway-component)
- [ACM Component](#acm-component)
- [DNS Component](#dns-component)
- [Backend Component](#backend-component)
- [Secrets Manager Component](#secretsmanager-component)
- [External Secrets Component](#external-secrets-component)
- [EKS Add-ons Component](#eks-addons-component)

---

## Common Variables

These variables are used across multiple components and should be defined in base configuration.

### region

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | AWS region where resources will be created |
| **Validation** | Must match pattern: `^[a-z]{2}(-[a-z]+)+-\d+$` |
| **Example** | `us-east-1`, `eu-west-2`, `ap-southeast-1` |

### tags

| Property | Value |
|----------|-------|
| **Type** | `map(string)` |
| **Required** | Yes |
| **Default** | `{}` |
| **Description** | Common tags applied to all resources |
| **Required Keys** | `Environment`, `ManagedBy`, `Tenant` |
| **Example** | `{ Environment = "production", ManagedBy = "terraform", Tenant = "mycompany" }` |

### environment

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | Environment name (dev, staging, prod) |
| **Valid Values** | `dev`, `staging`, `prod`, `test` |
| **Example** | `prod` |

### tenant

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | Tenant/organization identifier |
| **Example** | `mycompany`, `client-a` |

---

## VPC Component

### vpc_cidr

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | CIDR block for the VPC |
| **Validation** | Must be valid IPv4 CIDR block |
| **Example** | `10.0.0.0/16` |

**Recommendations:**
- Development: `10.0.0.0/16` (65,536 IPs)
- Staging: `10.10.0.0/16` (65,536 IPs)
- Production: `10.20.0.0/16` (65,536 IPs)

### azs

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | Availability Zones for subnet distribution |
| **Minimum** | 2 AZs |
| **Recommended** | 3 AZs |
| **Example** | `["us-east-1a", "us-east-1b", "us-east-1c"]` |

### private_subnets

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | CIDR blocks for private subnets (one per AZ) |
| **Validation** | Must be valid IPv4 CIDR blocks within VPC CIDR |
| **Example** | `["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]` |

### public_subnets

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | CIDR blocks for public subnets (one per AZ) |
| **Validation** | Must be valid IPv4 CIDR blocks within VPC CIDR |
| **Example** | `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` |

### database_subnets

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | No |
| **Default** | `[]` |
| **Description** | CIDR blocks for database subnets (one per AZ) |
| **Example** | `["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]` |

### enable_nat_gateway

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable NAT Gateway for private subnet internet access |
| **Example** | `true` |

### single_nat_gateway

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `false` |
| **Description** | Use single NAT Gateway (cost optimization, reduces HA) |
| **Recommendation** | `true` for dev/staging, `false` for production |
| **Example** | `true` |

### enable_flow_logs

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable VPC Flow Logs for network monitoring |
| **Example** | `true` |

### enable_dns_hostnames

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable DNS hostnames in the VPC |
| **Example** | `true` |

### enable_dns_support

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable DNS support in the VPC |
| **Example** | `true` |

### management_cidr

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | No |
| **Default** | `null` |
| **Description** | CIDR block for management access (SSH, etc.) |
| **Example** | `203.0.113.0/24` |

---

## EKS Component

### clusters

| Property | Value |
|----------|-------|
| **Type** | `map(object)` |
| **Required** | Yes |
| **Default** | `{}` |
| **Description** | Map of EKS cluster configurations |

**Cluster Object Schema:**
```hcl
{
  enabled                   = optional(bool, true)
  kubernetes_version        = optional(string, "1.28")
  endpoint_private_access   = optional(bool, true)
  endpoint_public_access    = optional(bool, false)
  subnet_ids                = optional(list(string))
  security_group_ids        = optional(list(string), [])
  kms_key_arn               = optional(string)
  enabled_cluster_log_types = optional(list(string), ["api", "audit"])
  node_groups               = optional(map(object), {})
  tags                      = optional(map(string), {})
}
```

**Example:**
```yaml
clusters:
  primary:
    kubernetes_version: "1.28"
    endpoint_private_access: true
    endpoint_public_access: false
    enabled_cluster_log_types: ["api", "audit", "authenticator"]
    node_groups:
      system:
        instance_types: ["m5.large"]
        desired_size: 3
        min_size: 3
        max_size: 5
```

### subnet_ids

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | Subnet IDs for EKS cluster |
| **Validation** | Minimum 2 subnets, must span 2+ AZs |
| **Example** | `["subnet-abc123", "subnet-def456", "subnet-ghi789"]` |

### default_kubernetes_version

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | No |
| **Default** | `"1.28"` |
| **Description** | Default Kubernetes version for clusters |
| **Valid Values** | `"1.27"`, `"1.28"`, `"1.29"`, `"1.30"` |
| **Example** | `"1.29"` |

### enable_cluster_protection

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable prevent_destroy lifecycle for production clusters |
| **Example** | `true` |

### default_cluster_log_retention_days

| Property | Value |
|----------|-------|
| **Type** | `number` |
| **Required** | No |
| **Default** | `90` |
| **Description** | CloudWatch log retention period (days) |
| **Valid Values** | `1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653` |
| **Example** | `90` |

### Node Group Object Schema

```hcl
node_groups = {
  "<name>" = {
    instance_types  = list(string)       # ["m5.large", "m5.xlarge"]
    ami_type        = string             # "AL2_x86_64"
    capacity_type   = string             # "ON_DEMAND" or "SPOT"
    disk_size       = number             # 50
    desired_size    = number             # 3
    min_size        = number             # 1
    max_size        = number             # 10
    taints          = list(object)       # Kubernetes taints
    labels          = map(string)        # Kubernetes labels
    tags            = map(string)        # AWS tags
  }
}
```

**Example:**
```yaml
node_groups:
  system:
    instance_types: ["m5.large"]
    capacity_type: "ON_DEMAND"
    desired_size: 3
    min_size: 3
    max_size: 5
    disk_size: 50
    labels:
      role: "system"

  application:
    instance_types: ["c5.xlarge", "c5a.xlarge"]
    capacity_type: "SPOT"
    desired_size: 5
    min_size: 2
    max_size: 20
    labels:
      role: "application"
    taints:
      - key: "dedicated"
        value: "application"
        effect: "NoSchedule"
```

---

## RDS Component

### vpc_id

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | VPC ID where RDS instance will be created |
| **Validation** | Must match pattern: `^vpc-[a-f0-9]+$` |
| **Example** | `"vpc-abc123def456"` |

### subnet_ids

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | Subnet IDs for DB subnet group |
| **Minimum** | 2 subnets in different AZs |
| **Example** | `["subnet-abc123", "subnet-def456"]` |

### engine

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | No |
| **Default** | `"aurora-mysql"` |
| **Description** | Database engine type |
| **Valid Values** | `"aurora-mysql"`, `"aurora-postgresql"`, `"mysql"`, `"postgres"` |
| **Example** | `"aurora-mysql"` |

### engine_version

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | No |
| **Default** | `"8.0.mysql_aurora.3.02.0"` |
| **Description** | Database engine version |
| **Example** | `"8.0.mysql_aurora.3.02.0"` |

### instance_class

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | Yes |
| **Default** | N/A |
| **Description** | RDS instance class |
| **Examples** | `db.t3.medium` (dev), `db.r5.large` (staging), `db.r5.xlarge` (prod) |

### allocated_storage

| Property | Value |
|----------|-------|
| **Type** | `number` |
| **Required** | No |
| **Default** | `100` |
| **Description** | Allocated storage in GB |
| **Minimum** | `20` |
| **Maximum** | `65536` |
| **Example** | `500` |

### multi_az

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `false` |
| **Description** | Enable Multi-AZ deployment |
| **Recommendation** | `false` for dev/staging, `true` for production |
| **Example** | `true` |

### backup_retention_period

| Property | Value |
|----------|-------|
| **Type** | `number` |
| **Required** | No |
| **Default** | `7` |
| **Description** | Backup retention period in days |
| **Range** | `0-35` (0 disables backups) |
| **Recommendation** | `7` for dev, `14` for staging, `30` for production |
| **Example** | `7` |

### skip_final_snapshot

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `false` |
| **Description** | Skip final snapshot on deletion |
| **Recommendation** | `true` for dev, `false` for staging/production |
| **Example** | `false` |

### allowed_security_groups

| Property | Value |
|----------|-------|
| **Type** | `list(string)` |
| **Required** | No |
| **Default** | `[]` |
| **Description** | Security group IDs allowed to connect |
| **Example** | `["sg-abc123", "sg-def456"]` |

### performance_insights_enabled

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `false` |
| **Description** | Enable Performance Insights |
| **Recommendation** | `true` for production |
| **Example** | `true` |

### deletion_protection

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `false` |
| **Description** | Enable deletion protection |
| **Recommendation** | `true` for production |
| **Example** | `true` |

---

## IAM Component

### create_roles

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Create IAM roles |
| **Example** | `true` |

### roles

| Property | Value |
|----------|-------|
| **Type** | `map(object)` |
| **Required** | No |
| **Default** | `{}` |
| **Description** | Map of IAM roles to create |

**Role Object Schema:**
```hcl
{
  description            = string
  assume_role_policy     = string
  managed_policy_arns    = list(string)
  inline_policies        = map(string)
  max_session_duration   = number
  tags                   = map(string)
}
```

**Example:**
```yaml
roles:
  eks-node-role:
    description: "IAM role for EKS worker nodes"
    assume_role_policy: |
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": {"Service": "ec2.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }]
      }
    managed_policy_arns:
      - "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
      - "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
```

---

## Monitoring Component

### create_cloudwatch_dashboard

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Create CloudWatch dashboard |
| **Example** | `true` |

### alarm_sns_topic_arn

| Property | Value |
|----------|-------|
| **Type** | `string` |
| **Required** | No |
| **Default** | `""` |
| **Description** | SNS topic ARN for alarm notifications |
| **Example** | `"arn:aws:sns:us-east-1:123456789012:alerts"` |

### enable_container_insights

| Property | Value |
|----------|-------|
| **Type** | `bool` |
| **Required** | No |
| **Default** | `true` |
| **Description** | Enable Container Insights for EKS |
| **Example** | `true` |

---

## Security Group Component

### security_groups

| Property | Value |
|----------|-------|
| **Type** | `map(object)` |
| **Required** | Yes |
| **Default** | `{}` |
| **Description** | Map of security groups to create |

**Security Group Object Schema:**
```hcl
{
  description = string
  ingress_rules = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  egress_rules = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
}
```

**Example:**
```yaml
security_groups:
  eks-cluster:
    description: "Security group for EKS cluster"
    ingress_rules:
      - from_port: 443
        to_port: 443
        protocol: "tcp"
        cidr_blocks: ["10.0.0.0/16"]
        description: "Allow HTTPS from VPC"
    egress_rules:
      - from_port: 0
        to_port: 0
        protocol: "-1"
        cidr_blocks: ["0.0.0.0/0"]
        description: "Allow all outbound"
```

---

## Lambda Component

### functions

| Property | Value |
|----------|-------|
| **Type** | `map(object)` |
| **Required** | Yes |
| **Default** | `{}` |
| **Description** | Map of Lambda functions to create |

**Function Object Schema:**
```hcl
{
  runtime          = string             # "python3.11"
  handler          = string             # "index.handler"
  filename         = string             # "lambda.zip"
  source_code_hash = string
  memory_size      = number             # 128-10240
  timeout          = number             # 3-900
  environment      = map(string)
  layers           = list(string)
  vpc_config       = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
}
```

---

## Quick Reference Table

| Component | Key Variables | Documentation |
|-----------|---------------|---------------|
| **VPC** | vpc_cidr, private_subnets, public_subnets | [VPC README](../components/terraform/vpc/README.md) |
| **EKS** | clusters, subnet_ids, kubernetes_version | [EKS README](../components/terraform/eks/README.md) |
| **RDS** | engine, instance_class, multi_az | [RDS README](../components/terraform/rds/README.md) |
| **IAM** | roles, policies | [IAM README](../components/terraform/iam/README.md) |
| **Monitoring** | dashboards, alarms | [Monitoring README](../components/terraform/monitoring/README.md) |
| **Lambda** | functions, runtime | [Lambda README](../components/terraform/lambda/README.md) |

---

## Variable Naming Conventions

1. **Boolean variables**: Prefix with `enable_`, `is_`, or `has_`
   - `enable_flow_logs`, `is_production`, `has_backup`

2. **Count/Size variables**: Use `_count` or `_size` suffix
   - `node_count`, `instance_size`, `disk_size`

3. **CIDR blocks**: Use `_cidr` suffix
   - `vpc_cidr`, `management_cidr`

4. **Lists of IDs**: Use `_ids` suffix (plural)
   - `subnet_ids`, `security_group_ids`

5. **ARNs**: Use `_arn` suffix
   - `kms_key_arn`, `iam_role_arn`

---

## Configuration Best Practices

1. **Use catalog defaults** for common values
2. **Override in environment** for specific needs
3. **Validate inputs** with validation blocks
4. **Document custom variables** in component README
5. **Use type constraints** for complex objects
6. **Provide sensible defaults** where possible
7. **Include examples** in descriptions

---

## Additional Resources

- [Terraform Variable Documentation](https://www.terraform.io/docs/language/values/variables.html)
- [Atmos Variable Management](https://atmos.tools/core-concepts/components/terraform/variables/)
- [Component READMEs](../components/terraform/)
- [Architecture Documentation](./architecture/)

---

**Document Version**: 1.0
**Last Updated**: 2025-12-02
**Maintained By**: Platform Team
**Review Cycle**: Quarterly
