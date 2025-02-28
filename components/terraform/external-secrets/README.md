# External Secrets Component

This component installs and configures the External Secrets Operator for Kubernetes, which allows Kubernetes to use external secret management systems like AWS Secrets Manager.

## Overview

The External Secrets Operator extends the Kubernetes API with `ExternalSecret` resources, which pull secret data from external APIs and automatically create Kubernetes secrets. This component:

1. Installs the External Secrets Operator using Helm
2. Creates necessary IAM roles and policies for accessing AWS Secrets Manager
3. Sets up default SecretStores for general secrets and certificate-specific secrets
4. Enables certificate rotation using external secrets

## Usage

Include this component in your Atmos stack configuration:

```yaml
external-secrets:
  vars:
    enabled: true
    cluster_name: ${eks.outputs.cluster_name}
    host: ${eks.outputs.cluster_endpoint}
    cluster_ca_certificate: ${eks.outputs.cluster_certificate_authority_data}
    oidc_provider_arn: ${eks.outputs.oidc_provider_arn}
    oidc_provider_url: ${eks.outputs.oidc_provider_url}
    # Optional settings
    namespace: "external-secrets"
    service_account_name: "external-secrets"
    chart_version: "0.9.9"
    create_default_cluster_secret_store: true
    create_certificate_secret_store: true
```

## Certificate Management

This component enables improved certificate management by:

1. Creating a dedicated ClusterSecretStore for certificates
2. Enabling automatic certificate rotation
3. Separating certificate management from the EKS addons component

### Certificate Rotation Process

1. Store the certificate in AWS Secrets Manager
2. Create an ExternalSecret in Kubernetes pointing to the AWS Secret
3. External Secrets automatically creates and updates the Kubernetes Secret
4. When the certificate is updated in AWS Secrets Manager, it's automatically propagated to Kubernetes

## Integration with Istio

To use External Secrets with Istio for certificate management:

1. Store TLS certificates in AWS Secrets Manager with proper naming
2. Create an ExternalSecret in the istio-ingress namespace
3. Istio will automatically use the created Kubernetes Secret for TLS termination

## Dependencies

- EKS Cluster
- AWS Secrets Manager
- IAM roles with OIDC provider configured

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| region | AWS region | string | - |
| enabled | Whether to enable this component | bool | true |
| cluster_name | EKS cluster name | string | - |
| host | Kubernetes host | string | - |
| cluster_ca_certificate | Kubernetes cluster CA certificate | string | - |
| oidc_provider_arn | OIDC provider ARN | string | - |
| oidc_provider_url | OIDC provider URL | string | - |
| namespace | Kubernetes namespace | string | "external-secrets" |
| service_account_name | Service account name | string | "external-secrets" |
| chart_version | Helm chart version | string | "0.9.9" |
| create_default_cluster_secret_store | Create default secret store | bool | true |
| create_certificate_secret_store | Create certificate secret store | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| external_secrets_role_arn | ARN of the IAM role |
| external_secrets_role_name | Name of the IAM role |
| external_secrets_policy_arn | ARN of the IAM policy |
| external_secrets_policy_name | Name of the IAM policy |
| external_secrets_service_account | Name of the service account |
| external_secrets_namespace | Namespace |
| default_cluster_secret_store_name | Default SecretStore name |
| certificate_secret_store_name | Certificate SecretStore name |