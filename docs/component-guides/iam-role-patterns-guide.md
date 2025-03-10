# IAM Role Patterns Guide

_Last Updated: March 10, 2025_

This comprehensive guide outlines AWS IAM role patterns and best practices implemented within the Atmos framework. It provides detailed information on role structures, policy patterns, and implementation examples for various use cases.

## Table of Contents

- [Introduction](#introduction)
- [Core IAM Concepts](#core-iam-concepts)
- [Role Types and Use Cases](#role-types-and-use-cases)
- [Cross-Account Access Patterns](#cross-account-access-patterns)
- [Service-Linked Role Patterns](#service-linked-role-patterns)
- [Federated Access Patterns](#federated-access-patterns)
- [Least Privilege Patterns](#least-privilege-patterns)
- [Role Inheritance and Categorization](#role-inheritance-and-categorization)
- [Permission Boundary Patterns](#permission-boundary-patterns)
- [IAM Policy Conditions](#iam-policy-conditions)
- [Session Policies](#session-policies)
- [Role Management Automation](#role-management-automation)
- [Monitoring and Governance](#monitoring-and-governance)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Introduction

### Purpose of IAM Roles

IAM roles in AWS provide temporary credentials for entities that need to interact with AWS resources. Roles are essential for:

- Granting permissions to AWS services
- Enabling cross-account access
- Providing temporary access to users or applications
- Implementing security controls like least privilege
- Federating identities from external providers

### Role-Based Access Control in Atmos

The Atmos framework implements a comprehensive role-based access control (RBAC) strategy using IAM roles as the foundation. This approach:

- Standardizes role structure across environments
- Implements consistent naming conventions
- Enforces least privilege access controls
- Separates duties between accounts and environments
- Provides an inheritance model for role permissions

## Core IAM Concepts

### Role Components

Each AWS IAM role consists of these key components:

1. **Trust Policy**: Defines who can assume the role
2. **Permission Policies**: Define what the role can do
3. **Session Duration**: How long credentials are valid
4. **Path**: Organizational structure for roles

### Trust Relationship Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Permission Policy Structure

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::example-bucket/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Environment": "production"
        }
      }
    }
  ]
}
```

## Role Types and Use Cases

### Service Roles

Service roles allow AWS services to perform actions on your behalf:

```hcl
# Example Lambda service role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.name_prefix}-lambda-exec"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "s3-access"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject"
      ]
      Resource = "arn:aws:s3:::${var.source_bucket}/*"
    }]
  })
}
```

### Cross-Account Roles

Roles that enable access between AWS accounts:

```hcl
# Example cross-account access role
resource "aws_iam_role" "cross_account_role" {
  name = "${var.name_prefix}-cross-account"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.trusted_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Department": "DevOps"
        }
      }
    }]
  })
}
```

### Instance Profiles

Roles attached to EC2 instances:

```hcl
# Example EC2 instance profile
resource "aws_iam_role" "ec2_role" {
  name = "${var.name_prefix}-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
```

### Federation Roles

Roles for external identity providers:

```hcl
# Example for SAML federation
resource "aws_iam_role" "saml_role" {
  name = "${var.name_prefix}-saml-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_saml_provider.corporate_idp.arn
      }
      Action = "sts:AssumeRoleWithSAML"
      Condition = {
        StringEquals = {
          "SAML:aud": "https://signin.aws.amazon.com/saml"
        }
      }
    }]
  })
}
```

## Cross-Account Access Patterns

### Hub and Spoke Pattern

A central account manages identities with spoke accounts for workloads:

```
                                         
                                         
  Identity Account         Dev Account     
  (Hub)                │   (Spoke)         
                                         
                                         
                                   
                                          
                                          
                        │  Staging Account  
                            (Spoke)          
                                           
                                           
                                  
                                           
                                           
                             Prod Account    
                             (Spoke)         
                                           
                                           
```

Implementation:

```hcl
# Role in spoke account
resource "aws_iam_role" "developers_role" {
  name = "DevelopersRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.identity_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Role": "Developer"
        }
      }
    }]
  })
}

# Policy in identity account
resource "aws_iam_policy" "assume_spoke_role" {
  name = "AssumeSpokeRoles"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = [
        "arn:aws:iam::${var.dev_account_id}:role/DevelopersRole",
        "arn:aws:iam::${var.staging_account_id}:role/DevelopersRole"
      ]
    }]
  })
}
```

### Role Chaining

Chain roles across multiple accounts:

```
User → Role in Account A → Role in Account B → Role in Account C → AWS Resources
```

Implementation considerations:

- Maximum chain length: Limit to 2-3 hops for manageability
- Session duration: Each hop's duration can't exceed the previous role's session
- Permission boundaries: Apply at each level to restrict maximum permissions
- Audit trail: CloudTrail logs each role assumption in the chain

## Service-Linked Role Patterns

### Auto-Created Service Roles

Some AWS services create service-linked roles automatically:

```hcl
# Enable service that creates a service-linked role
resource "aws_config_configuration_recorder" "main" {
  name     = "main-recorder"
  role_arn = aws_iam_role.config_role.arn
  
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
  # This will automatically create the AWSServiceRoleForConfig
}
```

### Explicitly Created Service Roles

Explicitly create service-linked roles when needed:

```hcl
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "Service-linked role for Autoscaling"
}
```

## Federated Access Patterns

### Web Identity Federation

Federation with providers like Amazon Cognito:

```hcl
# Example Cognito identity pool with role mapping
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name = "${var.app_name}-identity-pool"
  allow_unauthenticated_identities = false
  
  openid_connect_provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_iam_role" "authenticated" {
  name = "${var.app_name}-authenticated-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "cognito-identity.amazonaws.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud": aws_cognito_identity_pool.main.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        }
      }
    }]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  
  roles = {
    authenticated = aws_iam_role.authenticated.arn
  }
}
```

### SAML Federation

Enterprise identity integration with SAML:

```hcl
# Example SAML provider and role
resource "aws_iam_saml_provider" "corporate_idp" {
  name                   = "corporate-idp"
  saml_metadata_document = file("${path.module}/metadata.xml")
}

resource "aws_iam_role" "saml_admin" {
  name = "SAMLAdminRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_saml_provider.corporate_idp.arn
      }
      Action = "sts:AssumeRoleWithSAML"
      Condition = {
        StringEquals = {
          "SAML:aud": "https://signin.aws.amazon.com/saml"
        }
        "ForAnyValue:StringLike" = {
          "SAML:sub": "*@example.com"
        }
      }
    }]
  })
}
```

### Role Mapping Strategies

Map external identities to specific roles:

```hcl
# Role mappings based on SAML attributes
resource "aws_iam_role" "developer_role" {
  name = "DeveloperRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_saml_provider.corporate_idp.arn
      }
      Action = "sts:AssumeRoleWithSAML"
      Condition = {
        StringEquals = {
          "SAML:aud": "https://signin.aws.amazon.com/saml"
        }
        "ForAnyValue:StringLike" = {
          "SAML:attr:Role": ["Developer", "Engineer"]
        }
      }
    }]
  })
}

resource "aws_iam_role" "admin_role" {
  name = "AdminRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_saml_provider.corporate_idp.arn
      }
      Action = "sts:AssumeRoleWithSAML"
      Condition = {
        StringEquals = {
          "SAML:aud": "https://signin.aws.amazon.com/saml"
        }
        "ForAnyValue:StringLike" = {
          "SAML:attr:Role": ["Administrator", "SysAdmin"]
        }
      }
    }]
  })
}
```

## Least Privilege Patterns

### Function-Specific Roles

Create roles for specific functions:

```hcl
# Example S3 read-only role
resource "aws_iam_role" "s3_reader" {
  name = "${var.name_prefix}-s3-reader"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_read_policy" {
  name = "s3-read-only"
  role = aws_iam_role.s3_reader.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.data_bucket}",
        "arn:aws:s3:::${var.data_bucket}/*"
      ]
    }]
  })
}
```

### Resource-Specific Policies

Limit permissions to specific resources:

```hcl
# Example DynamoDB table-specific permissions
resource "aws_iam_policy" "dynamodb_table_access" {
  name = "${var.name_prefix}-${var.table_name}-access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = [
        aws_dynamodb_table.this.arn,
        "${aws_dynamodb_table.this.arn}/index/*"
      ]
    }]
  })
}
```

### Attribute-Based Access Control (ABAC)

Implement ABAC using tags:

```hcl
# ABAC pattern with resource and principal tags
resource "aws_iam_policy" "tag_based_access" {
  name = "tag-based-ec2-access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:StartInstances",
        "ec2:StopInstances"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "aws:ResourceTag/Environment": "${aws:PrincipalTag/Environment}",
          "aws:ResourceTag/Project": "${aws:PrincipalTag/Project}"
        }
      }
    }]
  })
}
```

## Role Inheritance and Categorization

### Functional Role Inheritance

Implement role inheritance for functional areas:

```
               
  BaseDataRole   
       |         
        
        ↓
                                     
 DataAnalystRole        DataScientist  
       |                   |           
                             
        ↓                     ↓
                                     
  ReportingRole          MLModelRole   
                                     
```

Implementation:

```hcl
# Base policy for all data roles
resource "aws_iam_policy" "base_data_policy" {
  name = "BaseDataPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket}",
          "arn:aws:s3:::${var.data_bucket}/*"
        ]
      }
    ]
  })
}

# Data Analyst policy with additional permissions
resource "aws_iam_policy" "data_analyst_policy" {
  name = "DataAnalystPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach both policies to the Data Analyst role
resource "aws_iam_role" "data_analyst" {
  name = "DataAnalystRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "analyst_base" {
  role       = aws_iam_role.data_analyst.name
  policy_arn = aws_iam_policy.base_data_policy.arn
}

resource "aws_iam_role_policy_attachment" "analyst_specific" {
  role       = aws_iam_role.data_analyst.name
  policy_arn = aws_iam_policy.data_analyst_policy.arn
}
```

### Environment-Specific Role Categories

Categorize roles by environment:

```hcl
# Environment-specific role pattern
module "dev_roles" {
  source = "../modules/environment-roles"
  
  environment = "dev"
  account_id  = var.dev_account_id
  admins      = ["arn:aws:iam::${var.identity_account_id}:user/admin1"]
  developers  = ["arn:aws:iam::${var.identity_account_id}:user/dev1", "arn:aws:iam::${var.identity_account_id}:user/dev2"]
  readonly    = ["arn:aws:iam::${var.identity_account_id}:group/viewers"]
  
  additional_admin_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  ]
  
  additional_developer_policies = [
    aws_iam_policy.dev_additional_permissions.arn
  ]
}

module "prod_roles" {
  source = "../modules/environment-roles"
  
  environment = "prod"
  account_id  = var.prod_account_id
  admins      = ["arn:aws:iam::${var.identity_account_id}:role/SeniorAdmins"]
  developers  = [] # No direct developer access to production
  readonly    = ["arn:aws:iam::${var.identity_account_id}:group/viewers", "arn:aws:iam::${var.identity_account_id}:group/auditors"]
  
  additional_admin_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  ]
  
  # More restrictive permissions in production
  require_mfa = true
  session_duration = 3600 # 1 hour
}
```

## Permission Boundary Patterns

### Account Boundary

Establish maximum permissions for an entire account:

```hcl
# Account-wide permission boundary
resource "aws_iam_policy" "account_boundary" {
  name = "AccountPermissionBoundary"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "s3:*",
          "dynamodb:*",
          "rds:*",
          "lambda:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "organizations:*"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### Developer Boundary

Limit permissions for developers:

```hcl
# Developer permission boundary
resource "aws_iam_policy" "developer_boundary" {
  name = "DeveloperPermissionBoundary"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*",
          "s3:Get*",
          "s3:List*",
          "s3:Put*",
          "dynamodb:Describe*",
          "dynamodb:Get*",
          "dynamodb:Query",
          "dynamodb:Scan",
          "lambda:Get*",
          "lambda:List*",
          "lambda:Invoke*"
        ]
        Resource = "*"
      },
      {
        Effect = "Deny"
        Action = [
          "iam:*",
          "organizations:*",
          "ec2:DeleteVpc",
          "rds:Delete*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Apply boundary to developer role
resource "aws_iam_role" "developer" {
  name                 = "DeveloperRole"
  permissions_boundary = aws_iam_policy.developer_boundary.arn
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.identity_account_id}:group/Developers"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
```

### Per-Environment Boundaries

Create different boundaries for each environment:

```hcl
locals {
  environments = {
    dev = {
      allow_resource_deletion = true
      allow_admin_actions     = true
    }
    staging = {
      allow_resource_deletion = true
      allow_admin_actions     = false
    }
    prod = {
      allow_resource_deletion = false
      allow_admin_actions     = false
    }
  }
}

resource "aws_iam_policy" "environment_boundary" {
  for_each = local.environments
  
  name = "${each.key}PermissionBoundary"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "s3:*",
          "dynamodb:*",
          "lambda:*"
        ]
        Resource = "*"
      }],
      each.value.allow_resource_deletion ? [] : [{
        Effect = "Deny"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteVpc",
          "s3:DeleteBucket",
          "dynamodb:DeleteTable",
          "lambda:DeleteFunction"
        ]
        Resource = "*"
      }],
      each.value.allow_admin_actions ? [] : [{
        Effect = "Deny"
        Action = [
          "iam:*Policy*",
          "iam:*Role*"
        ]
        Resource = "*"
      }]
    )
  })
}
```

## IAM Policy Conditions

### IP-Based Restrictions

Restrict access by source IP:

```hcl
# IP-based restriction policy
resource "aws_iam_policy" "ip_restricted_access" {
  name = "IPRestrictedAccess"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Action = "*"
      Resource = "*"
      Condition = {
        NotIpAddress = {
          "aws:SourceIp": concat(
            var.corporate_ip_ranges,
            var.vpn_ip_ranges
          )
        }
      }
    }]
  })
}
```

### Time-Based Restrictions

Limit access to specific time windows:

```hcl
# Time-based restriction policy
resource "aws_iam_policy" "time_restricted_access" {
  name = "TimeRestrictedAccess"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Action = "*"
      Resource = "*"
      Condition = {
        DateGreaterThan = {
          "aws:CurrentTime": "2023-12-31T23:59:59Z"
        }
      }
    },
    {
      Effect = "Deny"
      Action = "*"
      Resource = "*"
      Condition = {
        NotIpAddress = {
          "aws:CurrentTime": ["2023-01-01T08:00:00Z", "2023-01-01T18:00:00Z"]
        }
      }
    }]
  })
}
```

### MFA Requirements

Enforce MFA for sensitive operations:

```hcl
# MFA enforcement policy
resource "aws_iam_policy" "require_mfa" {
  name = "RequireMFA"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      NotAction = [
        "iam:ChangePassword",
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ]
      Resource = "*"
      Condition = {
        BoolIfExists = {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }]
  })
}
```

### Tag-Based Conditions

Implement fine-grained control with tags:

```hcl
# Tag-based access policy
resource "aws_iam_policy" "tag_based_ec2_access" {
  name = "TagBasedEC2Access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:RebootInstances"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "ec2:ResourceTag/Owner": "${aws:username}"
        }
      }
    },
    {
      Effect = "Allow"
      Action = "ec2:CreateTags"
      Resource = "*"
      Condition = {
        StringEquals = {
          "ec2:CreateAction": "RunInstances"
        }
      }
    }]
  })
}
```

## Session Policies

### Limited Session Permissions

Reduce permissions for temporary sessions:

```hcl
# Example of using AssumeRole with a session policy
resource "aws_iam_role" "admin_role" {
  name = "AdminRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.identity_account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
  
  # Admin permissions
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

# Example CLI command to assume role with a session policy
# aws sts assume-role \
#   --role-arn arn:aws:iam::123456789012:role/AdminRole \
#   --role-session-name "RestrictedSession" \
#   --policy '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"ec2:Describe*","Resource":"*"},{"Effect":"Deny","Action":"ec2:*Instance*","Resource":"*"}]}'
```

### Emergency Access

Implement emergency access patterns:

```hcl
# Emergency access role with MFA and logging
resource "aws_iam_role" "emergency_access" {
  name = "EmergencyAccessRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.identity_account_id}:role/EmergencyTeam"
      }
      Action = "sts:AssumeRole"
      Condition = {
        Bool = {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }]
  })
  
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  
  # Short session to limit exposure
  max_session_duration = 3600 # 1 hour
}

# CloudTrail and CloudWatch alerting for emergency access
resource "aws_cloudwatch_metric_alarm" "emergency_access_alarm" {
  alarm_name          = "EmergencyRoleAccess"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EmergencyRoleAssumed"
  namespace           = "AWS/IAM"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors emergency role assumption"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  
  dimensions = {
    RoleName = aws_iam_role.emergency_access.name
  }
}
```

## Role Management Automation

### Automated Role Creation

Automate role creation with Terraform modules:

```hcl
# Reusable role module
module "service_role" {
  source = "../modules/service-role"
  
  name                 = "lambda-processing-role"
  trusted_service      = "lambda.amazonaws.com"
  managed_policy_arns  = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  inline_policies      = {
    s3_access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.data_bucket}/*"]
      }]
    })
  }
  
  tags = {
    Service     = "Lambda"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```

### Automated Policy Generation

Generate policies from code:

```hcl
# Dynamic policy generation
locals {
  # List of S3 buckets with allowed actions
  s3_resources = [
    {
      bucket = "app-data-bucket"
      allowed_actions = ["s3:GetObject", "s3:ListBucket"]
    },
    {
      bucket = "app-logs-bucket"
      allowed_actions = ["s3:PutObject"]
    }
  ]
  
  # Generate policy statements for each bucket
  s3_policy_statements = [
    for resource in local.s3_resources : {
      Effect   = "Allow"
      Action   = resource.allowed_actions
      Resource = contains(resource.allowed_actions, "s3:ListBucket") 
        ? ["arn:aws:s3:::${resource.bucket}", "arn:aws:s3:::${resource.bucket}/*"]
        : ["arn:aws:s3:::${resource.bucket}/*"]
    }
  ]
}

resource "aws_iam_policy" "generated_s3_policy" {
  name = "GeneratedS3Policy"
  
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.s3_policy_statements
  })
}
```

### Role Rotation

Implement role rotation for enhanced security:

```hcl
# Role rotation pattern
resource "aws_iam_role" "rotatable_role" {
  name = "RotatableRole-${formatdate("YYYYMMDD", timestamp())}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  
  # Policies attached here
}

# Lambda function that updates service configuration to use the new role
resource "aws_lambda_function" "role_rotation_handler" {
  function_name = "role-rotation-handler"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  
  # Function code to update other services to use the new role
  # ...
}
```

## Monitoring and Governance

### Compliance Reporting

Monitor role compliance with AWS Config:

```hcl
# AWS Config rule for IAM policy compliance
resource "aws_config_config_rule" "iam_policy_no_statements_with_admin_access" {
  name        = "iam-policy-no-statements-with-admin-access"
  description = "Checks if AWS Identity and Access Management (IAM) policies grant admin privileges."

  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }
}

resource "aws_config_config_rule" "iam_user_no_policies_check" {
  name        = "iam-user-no-policies-check"
  description = "Checks that IAM users do not have policies attached."

  source {
    owner             = "AWS"
    source_identifier = "IAM_USER_NO_POLICIES_CHECK"
  }
}
```

### Access Analysis

Implement IAM Access Analyzer:

```hcl
# IAM Access Analyzer for external access identification
resource "aws_accessanalyzer_analyzer" "organization_analyzer" {
  analyzer_name = "organization-analyzer"
  type          = "ORGANIZATION"
}

# CloudWatch Events rule to notify on findings
resource "aws_cloudwatch_event_rule" "access_analyzer_finding" {
  name        = "access-analyzer-finding"
  description = "Capture Access Analyzer findings"

  event_pattern = jsonencode({
    source      = ["aws.access-analyzer"]
    detail-type = ["Access Analyzer Finding"]
    detail      = {
      status = ["ACTIVE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "access_analyzer_sns" {
  rule      = aws_cloudwatch_event_rule.access_analyzer_finding.name
  target_id = "AccessAnalyzerToSNS"
  arn       = aws_sns_topic.security_findings.arn
}
```

### Unused Access Reporting

Identify and remove unused permissions:

```hcl
# Lambda function to identify unused IAM permissions
resource "aws_lambda_function" "unused_permissions_reporter" {
  function_name = "unused-permissions-reporter"
  handler       = "index.handler"
  runtime       = "python3.9"
  
  environment {
    variables = {
      REPORT_BUCKET = aws_s3_bucket.compliance_reports.bucket
      LOOKBACK_DAYS = "90"
    }
  }
  
  # Function code to analyze CloudTrail and IAM permissions
  # ...
}

# Schedule regular analysis
resource "aws_cloudwatch_event_rule" "monthly_permission_analysis" {
  name                = "monthly-permission-analysis"
  description         = "Trigger unused permission analysis monthly"
  schedule_expression = "cron(0 0 1 * ? *)" # First day of each month
}

resource "aws_cloudwatch_event_target" "permission_analysis_lambda" {
  rule      = aws_cloudwatch_event_rule.monthly_permission_analysis.name
  target_id = "UnusedPermissionsLambda"
  arn       = aws_lambda_function.unused_permissions_reporter.arn
}
```

## Best Practices

### Role Naming Conventions

Implement consistent naming conventions:

- **Environment**: Include environment in the name (`dev-`, `prod-`)
- **Function**: Describe the role's purpose clearly (`lambda-execution-`)
- **Service**: Include the service name for service roles (`ec2-instance-profile-`)
- **Team**: Prefix with team name for team roles (`data-science-`)

Example naming pattern:
```
{environment}-{team}-{function}-{service}-role
```

### Security Best Practices

1. **Least Privilege**: Grant only required permissions
2. **Time-Limited Credentials**: Set reasonable session durations
3. **MFA Enforcement**: Require MFA for sensitive operations
4. **Regular Rotation**: Rotate credentials and review permissions regularly
5. **Permission Boundaries**: Use boundaries to limit maximum permissions
6. **Conditional Access**: Implement IP, time, and tag-based conditions
7. **Access Monitoring**: Log and monitor all role assumptions
8. **Regular Audits**: Perform regular security audits of roles and policies

### Common Pitfalls to Avoid

1. **Overly Permissive Policies**: Avoid using `"*"` for resources and actions
2. **Hardcoded ARNs**: Use variables and data sources instead of hardcoding ARNs
3. **Ignoring Policy Size Limits**: Remember the 6144 character limit for managed policies
4. **Mixing User and Role Permissions**: Keep user and role permissions separate
5. **Forgetting Trust Policy Updates**: Update trust policies when changing role structure
6. **Policy Variable Misuse**: Be careful with policy variables that can broaden access
7. **Missing Denies**: Use explicit Deny statements for critical restrictions
8. **Ignoring Permission Boundaries**: Always apply boundaries in dynamic environments

## Troubleshooting

### Common IAM Issues

| Issue | Common Causes | Solutions |
|-------|--------------|-----------|
| Access Denied | Insufficient permissions, incorrect resource ARN | Check policy permissions, validate resource ARNs |
| Unable to Assume Role | Trust policy issues, missing conditions | Check trust policy, verify caller identity, check conditions |
| Missing Expected Permissions | Policy precedence issues, service-linked role requirements | Review policy evaluation logic, check if service needs specific roles |
| Policy Too Large | Exceeded policy size limit | Break into multiple policies, use managed policies |
| Permission Boundary Conflicts | Boundary too restrictive | Review boundary policy and regular policy interactions |
| Cross-Account Access Issues | Trust relationship problems, organization constraints | Verify trust policy, check organization policies |

### Debugging IAM Permissions

Use these tools to debug IAM issues:

1. **IAM Policy Simulator**: Test policy evaluation
2. **CloudTrail**: Check for access denied events
3. **IAM Access Analyzer**: Identify potential security issues
4. **AWS CLI Dry Runs**: Use `--dry-run` for API calls
5. **Temporary Policy Expansion**: Temporarily expand permissions to isolate issues

Example IAM debugging with AWS CLI:

```bash
# Check who you are currently authenticated as
aws sts get-caller-identity

# Test policy simulation for a specific action
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/TestRole \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::example-bucket/test.txt

# Check CloudTrail for access denied events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AccessDenied
```

## References

- [AWS IAM Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Terraform AWS IAM Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)
- [Security Best Practices Guide](security-best-practices-guide.md)
- [AWS Authentication Guide](aws-authentication.md)
- [CI/CD Integration Guide](cicd-integration-guide.md)
- [Atmos Documentation](atmos-guide.md)