# Backend Component

This component sets up and manages Terraform state backends using AWS S3 and DynamoDB, providing a secure and centralized location for storing Terraform state files.

## Features

- S3 bucket for Terraform state files with versioning and encryption
- DynamoDB table for state locking
- Cross-account access policies
- Backend management IAM roles
- CORS configuration for web console access
- Bucket lifecycle rules for state file management
- Secure bucket policies preventing public access
- Access logging for state operations

## Usage

```hcl
module "backend" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/backend"
  
  region = var.region
  
  # S3 State Bucket Configuration
  state_bucket = {
    name                    = "my-terraform-state-bucket"
    versioning_enabled      = true
    enable_encryption       = true
    kms_key_id              = var.kms_key_id # Optional - uses default KMS key if not specified
    block_public_access     = true
    force_destroy           = false
    enable_access_logging   = true
    access_log_bucket_name  = "my-tfstate-access-logs"
    access_log_prefix       = "tfstate-logs"
    
    # Lifecycle Rules
    lifecycle_rules = [{
      id                     = "expire-old-versions"
      status                 = "Enabled"
      noncurrent_version_expiration = {
        days = 90
      }
    }]
    
    # CORS Configuration
    cors_rule = {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "PUT", "POST"]
      allowed_origins = ["https://console.aws.amazon.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  }
  
  # DynamoDB Lock Table Configuration
  lock_table = {
    name           = "my-terraform-lock-table"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "LockID"
    attribute_name = "LockID"
    attribute_type = "S"
  }
  
  # IAM Configuration
  create_backend_role = true
  backend_role_name   = "terraform-backend-role"
  account_ids_with_access = ["123456789012", "210987654321"]
  
  # Tags
  tags = {
    Environment = "management"
    Terraform   = "true"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| state_bucket | Configuration for the Terraform state S3 bucket | `any` | n/a | yes |
| lock_table | Configuration for the Terraform state lock DynamoDB table | `any` | n/a | yes |
| create_backend_role | Whether to create an IAM role for backend access | `bool` | `true` | no |
| backend_role_name | Name of the backend access IAM role | `string` | `"terraform-backend-role"` | no |
| account_ids_with_access | List of AWS account IDs that can access the backend | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| state_bucket_name | Name of the S3 bucket for Terraform state |
| state_bucket_arn | ARN of the S3 bucket for Terraform state |
| lock_table_name | Name of the DynamoDB table for state locking |
| lock_table_arn | ARN of the DynamoDB table for state locking |
| backend_role_arn | ARN of the IAM role for backend access |
| backend_role_name | Name of the IAM role for backend access |
| backend_configuration | Backend configuration for use in other components |

## Examples

### Basic Backend Configuration

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    backend/main:
      vars:
        region: us-west-2
        
        # S3 State Bucket
        state_bucket:
          name: "company-terraform-state-${var.environment}"
          versioning_enabled: true
          enable_encryption: true
          block_public_access: true
          force_destroy: false
          
          lifecycle_rules:
            - id: "expire-old-versions"
              status: "Enabled"
              noncurrent_version_expiration:
                days: 90
        
        # DynamoDB Lock Table
        lock_table:
          name: "company-terraform-lock-${var.environment}"
          billing_mode: "PAY_PER_REQUEST"
          hash_key: "LockID"
          attribute_name: "LockID"
          attribute_type: "S"
        
        # IAM Configuration
        create_backend_role: true
        backend_role_name: "terraform-backend-role-${var.environment}"
        
        # Tags
        tags:
          Environment: ${var.environment}
          Terraform: "true"
          Project: "infrastructure"
```

### Multi-Environment, Multi-Account Setup

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    backend/multi-account:
      vars:
        region: us-west-2
        
        # S3 State Bucket
        state_bucket:
          name: "company-terraform-state-central"
          versioning_enabled: true
          enable_encryption: true
          block_public_access: true
          force_destroy: false
          enable_access_logging: true
          access_log_bucket_name: "company-terraform-logs"
          access_log_prefix: "state-bucket-logs"
          
          lifecycle_rules:
            - id: "expire-old-versions"
              status: "Enabled"
              noncurrent_version_expiration:
                days: 90
            - id: "archive-old-versions"
              status: "Enabled"
              transition:
                days: 30
                storage_class: "STANDARD_IA"
        
        # DynamoDB Lock Table
        lock_table:
          name: "company-terraform-lock"
          billing_mode: "PAY_PER_REQUEST"
          hash_key: "LockID"
          attribute_name: "LockID"
          attribute_type: "S"
        
        # Cross-Account Access
        create_backend_role: true
        backend_role_name: "terraform-backend-role"
        account_ids_with_access:
          - "111111111111"  # Development account
          - "222222222222"  # Staging account
          - "333333333333"  # Production account
          - "444444444444"  # Security account
        
        # Tags
        tags:
          Environment: "management"
          Terraform: "true"
          Project: "infrastructure"
```

### Secure Production Configuration

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    backend/production:
      vars:
        region: us-west-2
        
        # S3 State Bucket with Enhanced Security
        state_bucket:
          name: "company-terraform-state-production"
          versioning_enabled: true
          enable_encryption: true
          kms_key_id: ${dep.kms.outputs.terraform_state_key_arn}
          block_public_access: true
          force_destroy: false
          enable_access_logging: true
          access_log_bucket_name: "company-logs-production"
          access_log_prefix: "tfstate-logs"
          
          lifecycle_rules:
            - id: "expire-old-versions"
              status: "Enabled"
              noncurrent_version_expiration:
                days: 365
            
          object_lock_configuration:
            object_lock_enabled: "Enabled"
            rule:
              default_retention:
                mode: "GOVERNANCE"
                days: 7
        
        # DynamoDB Lock Table
        lock_table:
          name: "company-terraform-lock-production"
          billing_mode: "PROVISIONED"
          read_capacity: 5
          write_capacity: 5
          hash_key: "LockID"
          attribute_name: "LockID"
          attribute_type: "S"
          point_in_time_recovery_enabled: true
        
        # IAM Configuration with Strict Permissions
        create_backend_role: true
        backend_role_name: "terraform-backend-role-production"
        require_mfa: true
        max_session_duration: 3600
        account_ids_with_access: ["444444444444"]  # Only CI/CD account
        
        # Tags
        tags:
          Environment: "production"
          Terraform: "true"
          Project: "infrastructure"
          DataClassification: "restricted"
```

## Implementation Best Practices

1. **Security**:
   - Always enable versioning to prevent state file loss
   - Enable encryption for state files at rest
   - Use KMS-managed keys for sensitive environments
   - Configure strict bucket policies to prevent unauthorized access
   - Enable access logging for audit purposes
   - Consider using Object Lock for critical environments
   - Implement MFA Delete for production buckets

2. **State Management**:
   - Set appropriate lifecycle rules to manage old state versions
   - Consider moving old state versions to cheaper storage classes
   - Enable point-in-time recovery for DynamoDB lock tables
   - Use separate state buckets for different security domains
   - For large organizations, consider a central management account for state

3. **Access Control**:
   - Implement least privilege IAM policies
   - Consider requiring MFA for production state access
   - Use separate IAM roles for different environments
   - Clearly tag all backend resources for better auditing
   - Regularly review and rotate access credentials

4. **Operational Excellence**:
   - Regularly backup state files to separate storage
   - Document backend configuration in a central location
   - Set up monitoring for backend access and operations
   - Consider implementing state file validation in CI/CD pipelines
   - Establish processes for state migration when needed