# AWS Secrets Manager Component

This component provides a flexible and secure way to manage secrets in AWS Secrets Manager. It supports creating multiple secrets, generating random passwords, configuring rotation, and applying access policies.

## Usage

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        enabled: true
        context_name: "myapp"
        name: "app-secrets"
        default_kms_key_id: "${output.kms.key_id}"
        
        secrets:
          db_password:
            name: "db-password"
            description: "Database password for application"
            path: "database"
            generate_random_password: true
          
          api_key:
            name: "api-key"
            description: "External API key"
            path: "integration"
            secret_data: "your-predefined-secret-value"
```

## Features

- **Hierarchical Secret Structure**: Organizes secrets with a hierarchical path structure (`context/environment/path/name`) for easy organization and discovery
- **Multiple Secrets Management**: Create and manage multiple secrets in a single module
- **Random Password Generation**: Automatically generate secure random passwords with configurable complexity
- **KMS Encryption**: Enforces encryption using customer-managed KMS keys
- **Secret Rotation**: Configure automatic secret rotation with AWS Lambda functions
- **IAM Policies**: Apply resource-based policies to control access to secrets
- **Structured Data**: Store structured JSON data in secrets
- **Cross-Account Access**: Manage cross-account access to secrets

## Secret Path Structure

Secrets are structured with the following path hierarchy:

```
<context_name>/<environment>/<path>/<name>
```

For example:
- `myapp/dev/database/credentials`
- `infra/prod/network/vpn-config`

This hierarchical structure ensures:
- Easy discovery of secrets
- Clean organization by application/context
- Environment isolation
- Logical grouping by functionality

## Secret Types

The component supports creating different types of secrets:

1. **Generated Passwords**: Set `generate_random_password: true` to automatically create secure random passwords
2. **Predefined Values**: Set `secret_data: "your-value"` to use a predefined secret value
3. **Structured Data**: Use JSON or YAML in the `secret_data` field for structured secrets

## Security Best Practices

This component enforces several security best practices:

1. **Encryption**: All secrets must be encrypted with a KMS key
2. **Rotation**: Configurable automatic rotation of secrets
3. **Recovery Window**: Configurable recovery window to prevent accidental deletion
4. **Complexity Rules**: Configurable password complexity for generated passwords
5. **Least Privilege**: Policy templates for read-only and administrative access

## Example: Database Credentials

```yaml
components:
  terraform:
    secretsmanager_db:
      vars:
        context_name: "myapp"
        name: "database-secrets"
        default_kms_key_id: "${output.kms.key_id}"
        
        secrets:
          master_credentials:
            name: "master-credentials"
            description: "RDS master credentials"
            path: "rds"
            generate_random_password: true
          
          connection_string:
            name: "connection-string"
            description: "Database connection string"
            path: "rds"
            secret_data: "postgresql://admin:${output.secretsmanager_db.generated_passwords.master_credentials}@${output.rds.endpoint}:5432/myapp"
```

## Example: Accessing Secrets

To access secrets from applications:

### AWS CLI
```bash
aws secretsmanager get-secret-value --secret-id myapp/dev/rds/master-credentials
```

### AWS SDK (JavaScript)
```javascript
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

async function getSecret(secretId) {
  const data = await secretsManager.getSecretValue({ SecretId: secretId }).promise();
  return data.SecretString;
}

// Usage
getSecret('myapp/dev/rds/master-credentials')
  .then(secret => console.log(secret))
  .catch(err => console.error(err));
```

### Terraform
```hcl
data "aws_secretsmanager_secret" "db_password" {
  name = "myapp/dev/rds/master-credentials"
}

data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = data.aws_secretsmanager_secret.db_password.id
}

# Access the secret value
locals {
  db_password = data.aws_secretsmanager_secret_version.db_password.secret_string
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| context_name | Context name for secret path hierarchy | `string` | n/a | yes |
| secrets | Map of secrets to create | `map(any)` | `{}` | yes |
| default_kms_key_id | Default KMS key ID for encrypting secrets | `string` | `null` | yes |
| default_rotation_days | Default days between rotations | `number` | `30` | no |
| default_rotation_automatically | Default auto-rotation setting | `bool` | `false` | no |
| default_recovery_window_in_days | Recovery window for deleted secrets | `number` | `30` | no |
| random_password_length | Length of generated random passwords | `number` | `32` | no |

## Outputs

| Name | Description |
|------|-------------|
| secret_arns | Map of secret names to their ARNs |
| secret_ids | Map of secret names to their secret IDs |
| secret_names | Map of secret names to their full path names |
| secret_versions | Map of secret names to their version IDs |
| generated_passwords | Map of secret names to their generated random passwords |