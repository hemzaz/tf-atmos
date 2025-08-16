# AWS Secrets Manager and Certificate Management Guide

_Last Updated: March 10, 2025_

This guide provides comprehensive information about using AWS Secrets Manager and certificate management in the Atmos framework to securely manage secrets and TLS certificates across your infrastructure.

## Table of Contents

- [Overview](#overview)
- [Secret Organization Strategy](#secret-organization-strategy)
- [Secret Types and Use Cases](#secret-types-and-use-cases)
- [Implementation Patterns](#implementation-patterns)
- [Security Best Practices](#security-best-practices)
- [Accessing Secrets](#accessing-secrets)
- [Certificate Management with External Secrets](#certificate-management-with-external-secrets)
- [Common Patterns and Examples](#common-patterns-and-examples)
- [Troubleshooting](#troubleshooting)
- [Best Practices Summary](#best-practices-summary)

## Overview

AWS Secrets Manager helps you protect access to your applications, services, and IT resources without the upfront cost and complexity of deploying and maintaining a specialized secrets management infrastructure. Combined with External Secrets for Kubernetes integration and AWS Certificate Manager for TLS certificates, this solution allows you to:

- Store and manage secrets with hierarchical organization
- Generate and rotate secrets automatically
- Control access with fine-grained policies
- Encrypt secrets with KMS keys
- Access secrets across accounts and services

## Secret Organization Strategy

### Hierarchical Path Structure

All secrets follow a consistent path structure:

```
<context_name>/<environment>/<path>/<n>
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

## Secret Types and Use Cases

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

## Implementation Patterns

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

## Security Best Practices

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

## Accessing Secrets

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

## Certificate Management with External Secrets

### Overview of Certificate Management

TLS certificates are critical security components that require special handling. This framework provides a comprehensive approach to certificate management using:

1. **AWS Certificate Manager (ACM)** for certificate issuance and automatic renewal
2. **AWS Secrets Manager** for secure storage of certificate references
3. **External Secrets Operator** for syncing certificates to Kubernetes
4. **Monitoring** for tracking certificate expiry and status

### External Secrets Component

A dedicated `external-secrets` component has been created to improve certificate management:

```yaml
external-secrets:
  vars:
    enabled: true
    cluster_name: ${eks.outputs.cluster_name}
    host: ${eks.outputs.cluster_endpoint}
    cluster_ca_certificate: ${eks.outputs.cluster_certificate_authority_data}
    oidc_provider_arn: ${eks.outputs.oidc_provider_arn}
    oidc_provider_url: ${eks.outputs.oidc_provider_url}
    create_certificate_secret_store: true
```

This component:
- Deploys the External Secrets Operator via Helm
- Creates necessary IAM roles and policies
- Sets up a dedicated ClusterSecretStore for certificates
- Enables automatic certificate rotation

### Certificate Rotation Process

1. Certificate is created or renewed in AWS ACM
2. Certificate reference is stored in AWS Secrets Manager
3. External Secrets syncs the reference to Kubernetes
4. Istio or other services use the Kubernetes secret

### Helper Scripts

Two helper scripts are provided to facilitate certificate management:

1. **export-cert.sh**: Exports certificate metadata and creates templates
   ```bash
   ./export-cert.sh -a <acm_certificate_arn> -r <aws_region> -o <output_directory>
   ```

2. **rotate-cert.sh**: Automates certificate rotation using External Secrets
   ```bash
   ./rotate-cert.sh -a <acm_certificate_arn> -r <aws_region> -k <k8s_namespace>/<k8s_secret_name> -e
   ```

### Certificate Monitoring

CloudWatch dashboards are provided to monitor certificate expiry:

```yaml
monitoring:
  vars:
    enable_certificate_monitoring: true
    certificate_arns: ${acm.outputs.certificate_arns}
    certificate_expiry_threshold: 30
```

## Common Patterns and Examples

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

### TLS Certificate Management with Istio

1. Create ACM certificate:
   ```yaml
   acm:
     vars:
       dns_domains:
         main_wildcard:
           domain_name: "*.example.com"
           validation_method: "DNS"
   ```

2. Store reference in Secrets Manager:
   ```yaml
   secretsmanager:
     vars:
       secrets:
         istio_cert:
           name: "wildcard-example-com-cert"
           path: "certificates"
           secret_data: |
             {
               "certificate": "ACM_PLACEHOLDER",
               "private_key": "ACM_PLACEHOLDER",
               "acm_arn": "${acm.outputs.certificate_arns.main_wildcard}"
             }
   ```

3. Create ExternalSecret in Kubernetes:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: wildcard-example-com-tls
     namespace: istio-ingress
   spec:
     refreshInterval: "1h"
     secretStoreRef:
       name: aws-certificate-store
       kind: ClusterSecretStore
     target:
       name: wildcard-example-com-tls
     data:
     - secretKey: tls.crt
       remoteRef:
         key: "certificates/wildcard-example-com-cert"
         property: certificate
     - secretKey: tls.key
       remoteRef:
         key: "certificates/wildcard-example-com-cert"
         property: private_key
   ```
   
## Troubleshooting

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

## Best Practices Summary

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