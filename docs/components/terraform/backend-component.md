# Backend Component

_Last Updated: February 28, 2025_

## Overview

The Backend component provisions and manages AWS infrastructure for secure and scalable Terraform state management, including S3 buckets for state storage and DynamoDB tables for state locking.

This component establishes a robust and secure backend infrastructure for Terraform state management in AWS. It creates an S3 bucket for state storage with proper encryption, versioning, and access controls, as well as a DynamoDB table for state locking to prevent concurrent operations conflicts. The component also sets up appropriate IAM roles and policies for secure access.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Terraform Backend                       │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  ┌─────────────────┐      ┌─────────────────────────┐   │
│  │  DynamoDB Table │      │     S3 Bucket           │   │
│  │  (State Locking)│◄────►│  (State Storage)        │   │
│  └─────────────────┘      └─────────────────────────┘   │
│                                      │                   │
│                                      ▼                   │
│                           ┌─────────────────────────┐   │
│                           │ KMS Key                 │   │
│                           │ (Encryption)            │   │
│                           └─────────────────────────┘   │
│                                      │                   │
│                            ┌─────────┴─────────┐        │
│                            ▼                   ▼        │
│         ┌─────────────────────────┐ ┌─────────────────┐ │
│         │ Access Logs Bucket      │ │ S3 Bucket Logs  │ │
│         └─────────────────────────┘ └─────────────────┘ │
│                                                         │
│  ┌────────────────────────────────────────────────┐     │
│  │               IAM Role                         │     │
│  │  (Backend Access with Least Privilege Policy)  │     │
│  └────────────────────────────────────────────────┘     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Features

- S3 bucket for Terraform state storage with versioning enabled
- DynamoDB table for state locking to prevent concurrent modifications
- KMS-managed encryption for state files at rest
- IAM role with least-privilege policies for backend access
- Server-side encryption for all state files
- Bucket policies to enforce HTTPS connections
- Complete blocking of public access
- Access logging for audit and compliance
- Lifecycle policies for managing state file versions
- MFA delete protection for state files
- Separate logging buckets to avoid circular dependencies

## Usage

### Basic Usage

```yaml
components:
  terraform:
    backend:
      vars:
        tenant: "mycompany"
        bucket_name: "mycompany-terraform-state"
        dynamodb_table_name: "mycompany-terraform-locks"
        region: "us-east-1"
        iam_role_name: "terraform-backend-role"
```

### Multi-Account Setup

```yaml
components:
  terraform:
    backend:
      vars:
        tenant: "mycompany"
        bucket_name: "mycompany-terraform-state-central"
        dynamodb_table_name: "mycompany-terraform-locks"
        region: "us-east-1"
        iam_role_name: "terraform-backend-role"
        account_id: "123456789012"  # Management account
        tags:
          Environment: "management"
          Project: "infrastructure"
          ManagedBy: "terraform"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `tenant` | Tenant name for resource naming | `string` | `""` | Yes |
| `account_id` | AWS Account ID for resource policies | `string` | `""` | Yes |
| `bucket_name` | Name of the S3 bucket for Terraform state | `string` | `""` | Yes |
| `dynamodb_table_name` | Name of the DynamoDB table for Terraform state locking | `string` | `""` | Yes |
| `region` | AWS region | `string` | `""` | Yes |
| `state_file_key` | Key for the state file in S3 bucket | `string` | `"terraform.tfstate"` | No |
| `iam_role_name` | Name of the IAM role to assume for Terraform execution | `string` | `""` | Yes |
| `iam_role_arn` | ARN of the IAM role to assume for Terraform execution | `string` | `""` | No |
| `tags` | Common tags to apply to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `backend_bucket` | The S3 bucket used for storing Terraform state |
| `backend_bucket_arn` | The ARN of the S3 bucket used for storing Terraform state |
| `dynamodb_table` | The DynamoDB table used for Terraform state locking |
| `dynamodb_table_arn` | The ARN of the DynamoDB table used for Terraform state locking |
| `backend_role_arn` | The ARN of the IAM role for backend access |

## Examples

### Basic Backend Setup

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    backend:
      vars:
        tenant: "mycompany"
        bucket_name: "mycompany-terraform-state-${vars.environment}"
        dynamodb_table_name: "mycompany-terraform-locks-${vars.environment}"
        region: ${vars.region}
        iam_role_name: "terraform-backend-role-${vars.environment}"
        
        tags:
          Environment: ${vars.environment}
          Project: "infrastructure"
          ManagedBy: "terraform"
```

### Production Environment with Enhanced Security

```yaml
# Stack configuration (production.yaml)
components:
  terraform:
    backend:
      vars:
        tenant: "mycompany"
        bucket_name: "mycompany-terraform-state-prod"
        dynamodb_table_name: "mycompany-terraform-locks-prod"
        region: "us-east-1"
        iam_role_name: "terraform-backend-role-prod"
        
        # Enable strict configurations for production
        # These are handled internally by the component
        # and just shown here for documentation
        # - MFA delete is enabled
        # - KMS encryption is applied
        # - Versioning is enabled
        # - Lifecycle rules apply for version management
        # - Access logging is enabled
        # - Public access is blocked
        
        tags:
          Environment: "production"
          Project: "infrastructure"
          ManagedBy: "terraform"
          DataClassification: "restricted"
```

### Multi-Account Access Configuration

```yaml
# Stack configuration (management.yaml)
components:
  terraform:
    backend:
      vars:
        tenant: "mycompany"
        bucket_name: "mycompany-terraform-state-mgmt"
        dynamodb_table_name: "mycompany-terraform-locks-mgmt"
        region: "us-east-1"
        iam_role_name: "terraform-backend-central-role"
        account_id: "123456789012"  # Management account
        
        # Cross-account access would be configured in assume role policies
        # These are handled at the IAM level and reference data source
        
        tags:
          Environment: "management"
          Project: "infrastructure"
          ManagedBy: "terraform"
```

## Implementation Best Practices

1. **Security**:
   - Always enable versioning to prevent state file loss
   - Use KMS-managed keys for encryption of state files
   - Enforce HTTPS-only access to state buckets
   - Implement MFA delete for critical state files
   - Block all public access to state buckets
   - Enable access logging for audit purposes

2. **Naming Conventions**:
   - Use consistent naming patterns for buckets and tables
   - Include tenant and environment in resource names
   - Use separate state files for different environments

3. **State Management**:
   - Implement appropriate lifecycle rules for state version management
   - Consider transitioning old state versions to cheaper storage classes
   - Regularly clean up or archive old state versions

4. **Access Control**:
   - Use least-privilege IAM policies for backend access
   - Consider separating read and write access with different IAM roles
   - Review and update access policies regularly

## Troubleshooting

### State Locking Issues

If you encounter state locking errors:

1. Check for abandoned locks in the DynamoDB table:
   ```bash
   aws dynamodb scan --table-name your-dynamodb-table-name --attributes-to-get LockID State
   ```

2. Manually release a lock if necessary (use with caution):
   ```bash
   aws dynamodb delete-item --table-name your-dynamodb-table-name --key '{"LockID": {"S": "your-state-file-path"}}'
   ```

### Access Denied Errors

1. Verify that your IAM user or role has the necessary permissions
2. Check that the backend role trust relationships are properly configured
3. Ensure you're using the correct AWS profile or credentials
4. Verify that the bucket and table exist in the region you're targeting

### State File Corruption or Loss

1. Restore from a previous S3 bucket version:
   ```bash
   aws s3api list-object-versions --bucket your-bucket-name --prefix your-state-file-path
   aws s3api get-object --bucket your-bucket-name --key your-state-file-path --version-id VERSION_ID state-backup.tf
   ```

2. Check access logs to determine what changes were made and by whom

## Related Components

- [IAM](../iam/README.md) - For additional IAM roles and policies
- [KMS](../kms/README.md) - For custom KMS keys if required

## Additional Resources

- [Terraform Backend Configuration](https://www.terraform.io/language/settings/backends/s3)
- [AWS S3 Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html)
- [AWS DynamoDB Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Introduction.html)
- [Atmos Workflow Documentation](../../docs/workflows.md)
- [Atmos Development Guide](../../docs/terraform-development-guide.md)