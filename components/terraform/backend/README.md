# Backend Component

_Last Updated: September 19, 2026_

## Overview

The Backend component provisions and manages AWS infrastructure for secure and scalable Terraform state management: an S3 bucket for state storage with S3-native state locking.

This component creates an S3 bucket for state storage with KMS encryption, versioning, ownership controls and a TLS-only bucket policy. State locking uses Terraform's S3-native lockfiles (`use_lockfile = true`, Terraform >= 1.10), which write a `<key>.tflock` object next to the state, so no DynamoDB lock table is created. The component also sets up an IAM role whose policy covers both the state and lock objects.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.16.0, < 2.0.0 |
| aws | ~> 6.65 |

Backends that use this bucket should set `use_lockfile = true` and drop `dynamodb_table`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Terraform Backend                       │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                                                         │
│             ┌──────────────────────────────────┐        │
│             │     S3 Bucket                    │        │
│             │  (State + .tflock lock objects)  │        │
│             └──────────────────────────────────┘        │
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
- S3-native state locking (`use_lockfile`), no DynamoDB table
- KMS-managed encryption for state files at rest
- IAM role with least-privilege policies for backend access
- Server-side encryption for all state files
- Bucket policies that deny non-TLS and pre-TLS 1.2 requests
- ACLs disabled (`BucketOwnerEnforced`) and complete blocking of public access
- Access logging for audit and compliance
- Lifecycle policies for managing state file versions
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
| `bucket_name` | Name of the S3 bucket for Terraform state (3-51 characters) | `string` | n/a | Yes |
| `enable_access_logging` | Create the access logs bucket and enable S3 server access logging | `bool` | `true` | No |
| `region` | AWS region | `string` | `""` | Yes |
| `iam_role_name` | Name of the IAM role to assume for Terraform execution | `string` | `""` | Yes |
| `tags` | Common tags to apply to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `backend_bucket` | The S3 bucket used for storing Terraform state |
| `backend_bucket_arn` | The ARN of the S3 bucket used for storing Terraform state |
| `backend_kms_key_arn` | The ARN of the KMS key encrypting Terraform state |
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
        region: "us-east-1"
        iam_role_name: "terraform-backend-role-prod"
        
        # Enable strict configurations for production
        # These are handled internally by the component
        # and just shown here for documentation
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
   - Block all public access to state buckets
   - Enable access logging for audit purposes

2. **Naming Conventions**:
   - Use consistent naming patterns for buckets
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

1. Release a stale lock with the lock ID from the error message (use with caution):
   ```bash
   terraform force-unlock LOCK_ID
   ```

2. If that fails, inspect and delete the lock object next to the state file:
   ```bash
   aws s3api head-object --bucket your-bucket-name --key your-state-file-path.tflock
   aws s3 rm s3://your-bucket-name/your-state-file-path.tflock
   ```

### Access Denied Errors

1. Verify that your IAM user or role has the necessary permissions
2. Check that the backend role trust relationships are properly configured
3. Ensure you're using the correct AWS profile or credentials
4. Verify that the bucket exists in the region you're targeting

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
- [Atmos Workflow Documentation](../../docs/workflows.md)
- [Atmos Development Guide](../../docs/terraform-development-guide.md)