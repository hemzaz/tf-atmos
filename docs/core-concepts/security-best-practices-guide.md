# Security Best Practices Guide

_Last Updated: March 10, 2025_

This comprehensive guide outlines security best practices for building, deploying, and maintaining infrastructure using the Atmos framework. It covers configurations, patterns, and operational guidance across all infrastructure layers.

## Table of Contents

- [Introduction](#introduction)
- [Foundational Security Principles](#foundational-security-principles)
- [AWS Account Security](#aws-account-security)
- [Network Security](#network-security)
- [Identity and Access Management](#identity-and-access-management)
- [Secrets Management](#secrets-management)
- [Data Protection](#data-protection)
- [Compute Security](#compute-security)
- [Kubernetes Security](#kubernetes-security)
- [Monitoring and Incident Response](#monitoring-and-incident-response)
- [Compliance and Governance](#compliance-and-governance)
- [Security Automation](#security-automation)
- [References](#references)

## Introduction

### Security-First Design Philosophy

The Atmos framework implements a security-first approach based on AWS best practices, Zero Trust principles, and defense-in-depth strategies. This guide provides security guidance in layers, from AWS account management to application-level controls.

### Multi-Account Architecture Security Benefits

The multi-account architecture pattern used by Atmos provides several security advantages:

- Strong security boundaries between environments
- Separation of duties and permissions
- Isolated blast radius for potential security incidents
- Simplified audit and compliance scoping
- Environment-specific security policies

## Foundational Security Principles

### Principle of Least Privilege

All components in Atmos follow the principle of least privilege, granting only the minimal permissions required for a service to function. This is implemented through:

- Granular IAM policies attached to specific service roles
- Time-bound credentials for human and machine identities
- Regular reviews and pruning of unused permissions

### Defense in Depth

Multiple security controls are layered throughout the infrastructure:

```
Network Security → Access Controls → Encryption → Monitoring → Compliance
```

### Secure Defaults

All Atmos components are configured with secure defaults:

- **Network**: All resources in private subnets by default
- **IAM**: Minimal permissions by default
- **Encryption**: AWS managed keys enabled by default
- **Access Logging**: Enabled by default for S3, CloudFront, ALB, etc.

## AWS Account Security

### Root User Security

Follow these best practices for root account security:

1. **MFA Enforcement**: Enable multi-factor authentication for the root user
2. **Limited Usage**: Only use the root user for tasks that explicitly require it
3. **No Access Keys**: Never create access keys for the root user
4. **Secure Recovery Options**: Use corporate email addresses and phone numbers

### AWS Organization Structure

```
                                                              
  Organization           Security OU             Workloads OU   
  Management          │  - Security             - Development   
  Account                - Logging           │  - Staging       
                         - Shared Svcs          - Production    
                                                                
```

### Service Control Policies (SCPs)

Implement SCPs to enforce organization-wide policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RequireIMDSv2",
      "Effect": "Deny",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:instance/*",
      "Condition": {
        "StringNotEquals": {
          "ec2:MetadataHttpTokens": "required"
        }
      }
    }
  ]
}
```

### AWS Config Rules

Essential AWS Config rules to implement:

| Rule | Purpose | Remediation |
|------|---------|-------------|
| `ROOT_ACCOUNT_MFA_ENABLED` | Ensures root user MFA is enabled | Enable MFA for root user |
| `IAM_USER_MFA_ENABLED` | Ensures MFA for all IAM users | Enforce MFA for all users |
| `IAM_PASSWORD_POLICY` | Enforces complex password policy | Update account password policy |
| `ENCRYPTED_VOLUMES` | Ensures all EBS volumes are encrypted | Use default encryption |
| `S3_BUCKET_PUBLIC_READ_PROHIBITED` | Prevents public S3 buckets | Remove public access |

## Network Security

### VPC Design

The [vpc component](../components/terraform/vpc) implements these security controls:

1. **Segmentation**: Strict separation between public, private, and data subnets
2. **Flow Logs**: VPC flow logs enabled and sent to CloudWatch Logs
3. **NACLs**: Network ACLs with explicit allow/deny rules
4. **Security Groups**: Minimal ingress/egress rules applied by default
5. **NAT Gateway**: Private subnets route outbound traffic through NAT
6. **PrivateLink**: Use AWS PrivateLink for service connections

### Security Group Patterns

Security group patterns in the [securitygroup component](../components/terraform/securitygroup):

```hcl
# Example of tiered application security group pattern
module "web_tier_sg" {
  source = "../modules/security-group"
  name   = "web-tier"
  rules = {
    ingress = [
      {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow HTTPS from internet"
      }
    ]
  }
}

module "app_tier_sg" {
  source = "../modules/security-group"
  name   = "app-tier"
  rules = {
    ingress = [
      {
        from_port       = 8080
        to_port         = 8080
        protocol        = "tcp"
        security_groups = [module.web_tier_sg.id]
        description     = "Allow traffic from web tier only"
      }
    ]
  }
}

module "data_tier_sg" {
  source = "../modules/security-group"
  name   = "data-tier"
  rules = {
    ingress = [
      {
        from_port       = 5432
        to_port         = 5432
        protocol        = "tcp"
        security_groups = [module.app_tier_sg.id]
        description     = "Allow traffic from app tier only"
      }
    ]
  }
}
```

### Transit Gateway Security

Secure multi-VPC connectivity with Transit Gateway:

1. Use resource access manager for cross-account sharing
2. Apply route table segmentation for traffic control
3. Enable flow logs for traffic inspection
4. Use Network Firewall for traffic inspection

## Identity and Access Management

### IAM Roles and Policies

IAM best practices implemented in the [iam component](../components/terraform/iam):

1. **Functional Roles**: Create roles for functions, not individuals
2. **Permission Boundaries**: Apply boundaries to limit maximum permissions
3. **Condition Keys**: Use condition keys to restrict access based on:
   - Source IP range
   - Time of day
   - Resource tags
   - MFA status
4. **Policy Structure**: Organize policies by resource and function

### Cross-Account Access

Secure pattern for cross-account access:

```hcl
# Role in target account
resource "aws_iam_role" "cross_account_role" {
  name = "cross-account-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.source_account_id}:role/source-role"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = { "aws:MultiFactorAuthPresent": "true" }
        }
      }
    ]
  })
}
```

### Temporary Credentials

Use temporary credentials with appropriate session duration:

| Identity Type | Maximum Duration | Recommended Duration |
|---------------|------------------|----------------------|
| Human users | 12 hours | 1 hour with MFA |
| CI/CD pipelines | 1 hour | 30 minutes |
| Long-running applications | 12 hours | 6 hours with rotation |

## Secrets Management

### Secrets Handling Pattern

The [secretsmanager component](../components/terraform/secretsmanager) implements these patterns:

1. **Hierarchical Organization**: `/environment/service/purpose`
2. **Automatic Rotation**: Lambda functions for key rotation
3. **Cross-Account Access**: Secure sharing between accounts
4. **Encryption Context**: Additional access controls with KMS
5. **Versioning**: Secret versioning for rotation management

### Integration with Infrastructure

```yaml
# Example stack configuration
components:
  terraform:
    rds:
      vars:
        master_password_secret_name: "${var.environment}/database/master-password"
        enable_automatic_rotation: true
        rotation_days: 30
```

### Kubernetes Integration

Use the [external-secrets component](../components/terraform/external-secrets) to securely inject AWS Secrets Manager secrets into Kubernetes:

```yaml
# Example ExternalSecret configuration
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
spec:
  refreshInterval: "15m"
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: db-creds
  data:
  - secretKey: username
    remoteRef:
      key: dev/database/credentials
      property: username
  - secretKey: password
    remoteRef:
      key: dev/database/credentials
      property: password
```

## Data Protection

### Encryption at Rest

Encryption practices for various AWS services:

| Service | Encryption Mechanism | Key Management |
|---------|----------------------|---------------|
| S3 | SSE-KMS with bucket policies | Customer managed keys |
| EBS | EBS encryption | AWS managed or customer managed |
| RDS | TDE with KMS | Customer managed keys |
| DynamoDB | Table encryption | AWS managed or customer managed |
| Lambda | Environment variable encryption | AWS managed keys |

### Encryption in Transit

1. **TLS Requirements**: TLS 1.2+ enforced for all services
2. **Certificate Management**: Automated with ACM
3. **Private Endpoints**: Use VPC endpoints with private DNS

### Data Classification

Apply data classification tags to all resources:

```hcl
# Example tags for data classification
tags = {
  "DataClassification" = "restricted"    # Options: public, internal, confidential, restricted
  "Compliance"         = "pci,hipaa"     # Relevant compliance programs
  "DataType"           = "pii,financial" # Type of data contained
}
```

## Compute Security

### EC2 Security

EC2 security practices in the [ec2 component](../components/terraform/ec2):

1. **IMDSv2**: Enforce IMDSv2 to prevent SSRF attacks
2. **Security Groups**: Restrict SSH access to VPN/bastion
3. **Volume Encryption**: Default encryption for all volumes
4. **Instance Profiles**: Least privilege IAM roles
5. **AMI Management**: Use hardened, regularly patched AMIs

```hcl
# Example EC2 security configuration
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # Enforce IMDSv2
  http_put_response_hop_limit = 1
}
```

### Lambda Security

Lambda security practices in the [lambda component](../components/terraform/lambda):

1. **Function Policies**: Granular resource-based policies
2. **VPC Deployment**: Place functions in private subnets
3. **Environment Variables**: Encrypt sensitive variables
4. **Third-Party Dependencies**: Scan dependencies for vulnerabilities
5. **Timeouts and Memory**: Set reasonable limits to prevent DoS

## Kubernetes Security

### EKS Security Baseline

EKS security practices in the [eks component](../components/terraform/eks):

1. **Private Cluster Endpoints**: Public endpoint disabled
2. **Control Plane Logging**: All log types enabled
3. **IRSA**: IAM Roles for Service Accounts for all pods
4. **Node Security**: Use managed node groups with latest AMIs
5. **Network Policies**: Enforce pod-to-pod traffic controls

### EKS Add-ons Security

Security-focused add-ons in the [eks-addons component](../components/terraform/eks-addons):

1. **AWS Load Balancer Controller**: Integrated security group management
2. **ExternalDNS**: Controlled DNS management
3. **Cert-Manager**: Automated certificate management
4. **Calico**: Enhanced network policies
5. **Kyverno**: Policy enforcement and governance

### Pod Security Standards

Enforce Pod Security Standards in Kubernetes:

```yaml
# Example Kyverno policy
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-pod-security-standards
spec:
  validationFailureAction: enforce
  rules:
    - name: restrict-privilege-escalation
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Privilege escalation is not allowed"
        pattern:
          spec:
            containers:
              - securityContext:
                  allowPrivilegeEscalation: false
```

## Monitoring and Incident Response

### Security Monitoring

Security monitoring implemented in the [monitoring component](../components/terraform/monitoring):

1. **CloudTrail**: Multi-region trail with validation
2. **VPC Flow Logs**: Captured and analyzed for anomalies
3. **GuardDuty**: Enabled with findings sent to Security account
4. **AWS Config**: Continuous compliance assessment
5. **Security Hub**: Aggregated findings and benchmarks

### Alerting Framework

```
CloudTrail/VPC Flow Logs → CloudWatch Logs → Log Insights → Alarms → SNS → Incident Management
```

### Incident Response Automation

Automate incident response with EventBridge:

```hcl
# Example EventBridge rule for suspicious activity
resource "aws_cloudwatch_event_rule" "guard_duty_findings" {
  name        = "guard-duty-findings"
  description = "Capture GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail      = {
      severity = [4, 5, 6, 7, 8]
    }
  })
}

resource "aws_cloudwatch_event_target" "remediation_lambda" {
  rule      = aws_cloudwatch_event_rule.guard_duty_findings.name
  target_id = "SecurityRemediationLambda"
  arn       = aws_lambda_function.security_remediation.arn
}
```

## Compliance and Governance

### Compliance Frameworks

The Atmos framework supports various compliance frameworks:

| Framework | Components | Documentation |
|-----------|------------|---------------|
| NIST 800-53 | All | [NIST Mapping Document](https://example.com/nist) |
| PCI DSS | All | [PCI Compliance Guide](https://example.com/pci) |
| HIPAA | All | [HIPAA Guide](https://example.com/hipaa) |
| SOC 2 | All | [SOC 2 Controls](https://example.com/soc2) |

### Automated Compliance Checks

Implement automated compliance with AWS Config and custom rules:

```hcl
# Example AWS Config rule for compliance
resource "aws_config_config_rule" "s3_bucket_ssl_requests_only" {
  name        = "s3-bucket-ssl-requests-only"
  description = "Checks whether S3 buckets have policies that require requests to use SSL"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }

  depends_on = [aws_config_configuration_recorder.main]
}
```

### Resource Tagging for Governance

Required tags for all resources:

```hcl
# Enforced tags for governance
locals {
  required_tags = {
    Environment     = var.environment
    Project         = var.project
    Owner           = var.owner
    CostCenter      = var.cost_center
    DataClassification = var.data_classification
    Compliance      = var.compliance_requirements
  }
}
```

## Security Automation

### Infrastructure as Code Security

Implement security checks in the CI/CD pipeline:

1. **Static Analysis**: TFSec, checkov for Terraform code
2. **Policy as Code**: Open Policy Agent for guardrails
3. **Drift Detection**: Regular checks for unauthorized changes
4. **Secret Scanning**: Detect hardcoded secrets in code

### Automatic Remediation

```yaml
# Example automatic remediation workflow
name: security-remediation
description: "Automatic remediation of security findings"
steps:
  - name: detect-public-s3
    command: aws
    args:
      - s3api
      - list-buckets
      - --query "Buckets[].Name"
      - --output text
    
  - name: check-public-access
    command: bash
    args:
      - -c
      - |
        for bucket in $(cat previous_step_output.txt); do
          aws s3api get-bucket-policy-status --bucket $bucket --query "PolicyStatus.IsPublic" --output text
          if [ $? -eq 0 ] && [ "$RESULT" == "true" ]; then
            echo "$bucket" >> public_buckets.txt
          fi
        done
    
  - name: remediate-public-buckets
    command: bash
    args:
      - -c
      - |
        for bucket in $(cat public_buckets.txt); do
          aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        done
```

## References

- [AWS Security Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [Terraform Security Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [IAM Role Patterns Guide](iam-role-patterns-guide.md)
- [Certificate Management Guide](certificate-management-guide.md)
- [Secrets Manager Guide](../docs-consolidated/secrets-manager-guide.md)
- [Cloud Security Alliance](https://cloudsecurityalliance.org/)