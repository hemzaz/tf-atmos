# IAM Component

This component manages AWS Identity and Access Management (IAM) resources including roles, policies, users, and groups.

## Features

- Create and manage IAM roles with trust relationships
- Define IAM policies with least privilege permissions
- Manage IAM users and groups
- Support for cross-account access
- Configure SAML federation for identity providers
- Set up service-linked roles for AWS services

## Usage

```hcl
module "iam" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/iam"
  
  region = var.region
  
  # IAM Roles
  roles = {
    "app-server" = {
      name               = "AppServerRole"
      assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      ]
      inline_policies = {
        "s3-access" = data.aws_iam_policy_document.s3_app_access.json
      }
      tags = {
        Environment = "production"
      }
    },
    "lambda-execution" = {
      name               = "LambdaExecutionRole"
      assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
      ]
      inline_policies = {
        "dynamodb-access" = data.aws_iam_policy_document.dynamodb_lambda_access.json
      }
      tags = {
        Environment = "production"
      }
    }
  }
  
  # Cross-Account Roles
  cross_account_roles = {
    "devops-access" = {
      name                = "DevOpsAccessRole"
      source_account_ids  = ["123456789012"]  # Account IDs allowed to assume this role
      role_policy_arns    = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      max_session_duration = 3600
      tags = {
        Environment = "all"
      }
    }
  }
  
  # IAM Policies
  policies = {
    "app-s3-access" = {
      name        = "AppS3Access"
      description = "Allows access to application S3 buckets"
      policy      = data.aws_iam_policy_document.s3_app_access.json
      tags = {
        Environment = "production"
      }
    }
  }
  
  # IAM Groups
  groups = {
    "developers" = {
      name       = "Developers"
      policies   = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      users      = ["dev1", "dev2"]
      path       = "/"
    }
  }
  
  # Global Tags
  tags = {
    Project     = "example"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| roles | Map of IAM roles to create | `map(any)` | `{}` | no |
| cross_account_roles | Map of cross-account roles to create | `map(any)` | `{}` | no |
| policies | Map of IAM policies to create | `map(any)` | `{}` | no |
| groups | Map of IAM groups to create | `map(any)` | `{}` | no |
| users | Map of IAM users to create | `map(any)` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| role_arns | Map of role names to ARNs |
| role_names | Map of role names to their names |
| policy_arns | Map of policy names to ARNs |
| group_arns | Map of group names to ARNs |
| user_arns | Map of user names to ARNs |
| instance_profiles | Map of instance profile names to ARNs |

## Examples

### Basic IAM Roles and Policies

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/base:
      vars:
        region: us-west-2
        
        # IAM Roles
        roles:
          app-server:
            name: "AppServerRole"
            assume_role_policy: |
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Action": "sts:AssumeRole",
                    "Principal": {
                      "Service": "ec2.amazonaws.com"
                    },
                    "Effect": "Allow",
                    "Sid": ""
                  }
                ]
              }
            managed_policy_arns:
              - "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
              - "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
            inline_policies:
              s3-access: |
                {
                  "Version": "2012-10-17",
                  "Statement": [
                    {
                      "Action": [
                        "s3:GetObject",
                        "s3:ListBucket"
                      ],
                      "Resource": [
                        "arn:aws:s3:::example-app-configs",
                        "arn:aws:s3:::example-app-configs/*"
                      ],
                      "Effect": "Allow"
                    }
                  ]
                }
            create_instance_profile: true
            tags:
              Environment: dev
        
        # Policies
        policies:
          app-dynamodb-access:
            name: "AppDynamoDBAccess"
            description: "Allow access to application DynamoDB tables"
            policy: |
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Action": [
                      "dynamodb:GetItem",
                      "dynamodb:Query",
                      "dynamodb:Scan"
                    ],
                    "Resource": [
                      "arn:aws:dynamodb:us-west-2:*:table/app-*"
                    ],
                    "Effect": "Allow"
                  }
                ]
              }
            tags:
              Environment: dev
```

### Cross-Account Access

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/cross-account:
      vars:
        region: us-west-2
        
        # Cross-Account Roles
        cross_account_roles:
          devops-access:
            name: "DevOpsAccessRole"
            source_account_ids: ["123456789012"]  # Account IDs allowed to assume this role
            role_policy_arns:
              - "arn:aws:iam::aws:policy/ReadOnlyAccess"
            inline_policies:
              custom-permissions: |
                {
                  "Version": "2012-10-17",
                  "Statement": [
                    {
                      "Action": [
                        "s3:ListBucket",
                        "s3:GetObject"
                      ],
                      "Resource": [
                        "arn:aws:s3:::example-logs",
                        "arn:aws:s3:::example-logs/*"
                      ],
                      "Effect": "Allow"
                    }
                  ]
                }
            max_session_duration: 7200
            tags:
              Environment: production
          
          ci-cd-access:
            name: "CICDPipelineRole"
            source_account_ids: ["987654321098"]
            role_policy_arns:
              - "arn:aws:iam::aws:policy/AmazonS3FullAccess"
              - "arn:aws:iam::aws:policy/AmazonECR-FullAccess"
            max_session_duration: 3600
            tags:
              Environment: production
```

### Identity Federation with SAML

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    iam/federation:
      vars:
        region: us-west-2
        
        # SAML Identity Provider
        identity_providers:
          okta:
            name: "OktaIdentityProvider"
            saml_metadata_document: "${file("./saml-metadata.xml")}"
        
        # Federation Roles
        roles:
          developers:
            name: "FederatedDevelopers"
            assume_role_policy: |
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Principal": {
                      "Federated": "arn:aws:iam::${var.account_id}:saml-provider/OktaIdentityProvider"
                    },
                    "Action": "sts:AssumeRoleWithSAML",
                    "Condition": {
                      "StringEquals": {
                        "SAML:aud": "https://signin.aws.amazon.com/saml"
                      }
                    }
                  }
                ]
              }
            managed_policy_arns:
              - "arn:aws:iam::aws:policy/ReadOnlyAccess"
            tags:
              Environment: production
          
          administrators:
            name: "FederatedAdministrators"
            assume_role_policy: |
              {
                "Version": "2012-10-17",
                "Statement": [
                  {
                    "Effect": "Allow",
                    "Principal": {
                      "Federated": "arn:aws:iam::${var.account_id}:saml-provider/OktaIdentityProvider"
                    },
                    "Action": "sts:AssumeRoleWithSAML",
                    "Condition": {
                      "StringEquals": {
                        "SAML:aud": "https://signin.aws.amazon.com/saml"
                      }
                    }
                  }
                ]
              }
            managed_policy_arns:
              - "arn:aws:iam::aws:policy/AdministratorAccess"
            tags:
              Environment: production
```

## Implementation Best Practices

1. **Security**:
   - Follow the principle of least privilege when granting permissions
   - Use managed policies when possible for easier maintenance
   - Regularly audit and rotate credentials
   - Use roles instead of long-term access keys
   - Implement MFA for critical operations
   - Never hardcode credentials in your code

2. **Organization**:
   - Use consistent naming conventions for all IAM resources
   - Use tags for resource organization and cost allocation
   - Group related permissions into logical policies
   - Document the purpose of each role and policy

3. **Cross-Account Access**:
   - Use roles for cross-account access instead of users
   - Limit the session duration for assumed roles
   - Implement strict conditions in trust relationships
   - Audit cross-account access regularly

4. **Federation**:
   - Use identity federation for enterprise integration
   - Map SAML attributes to IAM roles
   - Implement role-based access control using groups
   - Use attribute-based access control for fine-grained permissions

5. **Rotation and Monitoring**:
   - Implement credential rotation policies
   - Monitor for unused IAM users and roles
   - Set up CloudTrail logging for IAM actions
   - Use AWS Config rules to enforce IAM best practices