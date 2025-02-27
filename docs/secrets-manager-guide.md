# AWS Secrets Manager Integration Guide

_Last Updated: February 27, 2025_

This guide provides comprehensive information about using the AWS Secrets Manager component in the Atmos framework to securely manage and access secrets across your infrastructure.

## 1. Overview

AWS Secrets Manager helps you protect access to your applications, services, and IT resources without the upfront cost and complexity of deploying and maintaining a specialized secrets management infrastructure. This integration allows you to:

- Store and manage secrets with hierarchical organization
- Generate and rotate secrets automatically
- Control access with fine-grained policies
- Encrypt secrets with KMS keys
- Access secrets across accounts and services

## 2. Secret Organization Strategy

### Hierarchical Path Structure

All secrets follow a consistent path structure:

```
<context_name>/<environment>/<path>/<name>
```

- **Context Name**: Top-level grouping (e.g., application name, service name)
- **Environment**: Deployment environment (dev, staging, prod)
- **Path**: Logical grouping within the application/context
- **Name**: Specific secret identifier

### Example Paths

| Secret Path | Description |
|-------------|-------------|
| `myapp/dev/database/credentials` | Database credentials for dev environment |
| `myapp/prod/api/authentication` | API authentication for production |
| `infra/shared/vpn/certificates` | VPN certificates for shared infrastructure |

### Benefits of Hierarchical Structure

- **Organization**: Logically group related secrets
- **Access Control**: Apply IAM policies at different levels of the hierarchy
- **Automation**: Programmatically access secrets based on environment
- **Clarity**: Self-documenting naming convention

## 3. Secret Types and Use Cases

### Application Secrets

- Database credentials
- API keys
- OAuth tokens
- Encryption keys
- Service account credentials

### Infrastructure Secrets

- VPN configurations
- SSH keys
- Certificate private keys
- Monitoring system credentials
- Cloud provider API keys

### User Secrets

- Admin credentials
- MFA backup codes
- Recovery tokens

## 4. Implementation Patterns

### Basic Secret Creation

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        context_name: "myapp"
        name: "database-secrets"
        secrets:
          admin_password:
            name: "admin-password"
            path: "rds"
            generate_random_password: true
```

### Structured Secret Data

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        context_name: "myapp"
        name: "api-secrets"
        secrets:
          oauth_config:
            name: "oauth-config"
            path: "auth"
            secret_data: |
              {
                "clientId": "example-client-id",
                "clientSecret": "example-client-secret",
                "tokenEndpoint": "https://auth.example.com/oauth/token"
              }
```

### Secret References

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        context_name: "myapp"
        name: "connection-strings"
        secrets:
          db_connection:
            name: "database-url"
            path: "connections"
            secret_data: "postgresql://${output.rds.master_username}:${output.secretsmanager.generated_passwords.admin_password}@${output.rds.endpoint}:5432/${output.rds.db_name}"
```

## 5. Security Best Practices

### Encryption

Always specify a KMS key for encrypting secrets:

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        default_kms_key_id: "${output.kms.key_id}"
```

### Access Control

Implement least privilege using the policy templates:

- Use `read-secret-policy.json.tpl` for read-only access
- Use `admin-secret-policy.json.tpl` for administrative access
- Use `cross-account-secret-policy.json.tpl` for cross-account access

### Secret Rotation

Enable automatic rotation for critical secrets:

```yaml
components:
  terraform:
    secretsmanager:
      vars:
        secrets:
          api_key:
            rotation_automatically: true
            rotation_days: 30
            rotation_lambda_arn: "${output.lambda.rotation_function_arn}"
```

### Monitoring and Auditing

- Enable CloudTrail for Secret Manager API calls
- Set up CloudWatch alarms for suspicious access patterns
- Regularly audit secret access permissions

## 6. Accessing Secrets

### From EC2 Instances

```bash
# Install the AWS CLI
apt-get install -y awscli

# Get the secret
SECRET=$(aws secretsmanager get-secret-value --secret-id myapp/dev/database/credentials --query SecretString --output text)

# Use the secret
echo $SECRET | jq -r .password
```

### From ECS/EKS Container

```yaml
# Task definition excerpt
containerDefinitions:
  - name: app
    secrets:
      - name: DB_PASSWORD
        valueFrom: "arn:aws:secretsmanager:region:account:secret:myapp/dev/database/credentials-AbCdEf"
```

### From Lambda Functions

```javascript
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

exports.handler = async (event) => {
  try {
    const data = await secretsManager.getSecretValue({
      SecretId: 'myapp/dev/database/credentials'
    }).promise();
    
    const secret = JSON.parse(data.SecretString);
    // Use the secret...
  } catch (err) {
    console.error('Error retrieving secret:', err);
    throw err;
  }
};
```

### From Application Code

```java
// Java example
import com.amazonaws.services.secretsmanager.AWSSecretsManager;
import com.amazonaws.services.secretsmanager.AWSSecretsManagerClientBuilder;
import com.amazonaws.services.secretsmanager.model.GetSecretValueRequest;
import com.amazonaws.services.secretsmanager.model.GetSecretValueResult;

public class SecretsManagerExample {
    public static void getSecret() {
        AWSSecretsManager client = AWSSecretsManagerClientBuilder.standard().build();
        GetSecretValueRequest request = new GetSecretValueRequest()
            .withSecretId("myapp/dev/database/credentials");
        
        GetSecretValueResult result = client.getSecretValue(request);
        String secret = result.getSecretString();
        // Use the secret...
    }
}
```

## 7. Common Patterns and Examples

### Database Credentials Management

1. Generate random master password:
   ```yaml
   secrets:
     master_password:
       name: "master-password"
       path: "rds"
       generate_random_password: true
   ```

2. Create RDS instance using the password:
   ```yaml
   rds:
     vars:
       master_password: "${output.secretsmanager.generated_passwords.master_password}"
   ```

3. Store connection information as structured data:
   ```yaml
   secrets:
     connection_info:
       name: "connection-info"
       path: "rds"
       secret_data: |
         {
           "host": "${output.rds.endpoint}",
           "port": 5432,
           "username": "${output.rds.master_username}",
           "password": "${output.secretsmanager.generated_passwords.master_password}",
           "database": "${output.rds.db_name}"
         }
   ```

### API Integration Credentials

1. Create API key secret:
   ```yaml
   secrets:
     api_key:
       name: "external-api-key"
       path: "integration"
       secret_data: "your-api-key-value"
   ```

2. Reference in Lambda function:
   ```yaml
   lambda:
     vars:
       environment_variables:
         API_KEY_SECRET_ARN: "${output.secretsmanager.secret_arns.api_key}"
   ```

3. Access in the Lambda:
   ```javascript
   const secretsManager = new AWS.SecretsManager();
   const response = await secretsManager.getSecretValue({
     SecretId: process.env.API_KEY_SECRET_ARN
   }).promise();
   const apiKey = response.SecretString;
   ```

## 8. Troubleshooting

### Common Issues

| Issue | Possible Solution |
|-------|-------------------|
| Access Denied | Check IAM permissions for the calling identity |
| KMS Key Permissions | Ensure the KMS key policy allows the caller to use the key |
| Cross-Account Access | Verify resource policy allows the external account |
| Secret Not Found | Check for typos in the secret path |
| Rotation Failure | Verify Lambda has proper permissions and network access |

### Debugging Steps

1. Enable CloudTrail and check for access denied events
2. Verify KMS key policies allow the required operations
3. Check IAM permissions for the calling identity
4. Verify network connectivity for the rotation Lambda
5. Check CloudWatch logs for detailed error messages

## 9. Best Practices Summary

1. **Hierarchical Organization**: Use consistent path structure
2. **Encryption**: Always use KMS keys for encryption
3. **Least Privilege**: Apply the minimum necessary permissions
4. **Rotation**: Enable automatic rotation for sensitive secrets
5. **Distribution**: Never store secrets in code or config files
6. **Monitoring**: Set up alerts for suspicious activity
7. **Access Control**: Implement fine-grained access policies
8. **Cross-Account**: Use resource policies for cross-account access
9. **Documentation**: Document the purpose and access patterns for secrets
10. **References**: Use output references to link secrets to resources