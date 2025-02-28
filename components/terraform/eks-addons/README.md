# EKS Addons Component

This component provides a secure, flexible, and error-resistant way to deploy and manage AWS EKS addons, Helm charts, and Kubernetes manifests across multiple EKS clusters.

## Features

- Strongly typed inputs with comprehensive validation
- Support for AWS EKS native addons with version validation
- Helm chart deployment with customizable values
- Direct Kubernetes manifest application
- IAM integration for service accounts with proper permissions
- Certificate management and TLS termination
- Service mesh (Istio) integration with high availability settings
- Integration with External Secrets for improved certificate rotation
- Multi-cluster support with per-cluster configuration
- Error prevention with extensive validation blocks
- Clear deprecation warnings for legacy configuration patterns
- Fail-safe defaults to prevent common operational issues
- Advanced autoscaling with Karpenter and KEDA

## Architecture

This component is built with a multi-cluster design that enables managing multiple EKS clusters from a single deployment:

1. **Multiple Clusters Support**: Define and manage multiple EKS clusters through the `clusters` variable
2. **Resource Types**:
   - AWS EKS native addons (managed by AWS EKS)
   - Helm charts (deployed via the Helm provider)
   - Kubernetes manifests (applied directly via the Kubernetes provider)
3. **IAM Integration**: Automated IAM role creation for service accounts with IRSA
4. **Certificate Management**:
   - External Secrets integration for secure certificate handling
   - Direct certificate injection (legacy approach)
5. **Error Prevention**:
   - Controlled resource ordering with dependencies
   - Sleep timers to prevent race conditions
   - Validation blocks to catch misconfigurations early

## Usage

### Basic Configuration

```yaml
eks-addons:
  vars:
    enabled: true
    cluster_name: "my-cluster"
    region: "us-west-2"
    
    clusters:
      main:
        host: ${output.eks.cluster_endpoint}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificate}
        oidc_provider_arn: ${output.eks.oidc_provider_arn}
        
        # AWS EKS native addons
        addons:
          vpc-cni:
            name: "vpc-cni"
            version: "v1.13.4-eksbuild.1"
          
          coredns:
            name: "coredns"
            version: "v1.10.1-eksbuild.1"
        
        # Helm releases
        helm_releases:
          metrics-server:
            enabled: true
            chart: "metrics-server"
            repository: "https://kubernetes-sigs.github.io/metrics-server/"
            chart_version: "3.10.0"
            namespace: "kube-system"
        
        # Kubernetes manifests
        kubernetes_manifests:
          namespace-dev:
            enabled: true
            manifest: {
              "apiVersion": "v1",
              "kind": "Namespace",
              "metadata": {
                "name": "dev"
              }
            }
          namespace-prod:
            enabled: true
            manifest_yaml: |
              apiVersion: v1
              kind: Namespace
              metadata:
                name: prod
                labels:
                  environment: production
```

### Istio Service Mesh

This component supports deploying Istio Service Mesh with the following components:

- `istio-base`: Base CRDs and components
- `istiod`: Control plane
- `istio-ingress`: Ingress gateway
- `kiali`: Service mesh visualization
- `jaeger`: Distributed tracing

#### Istio Configuration

```yaml
eks-addons:
  vars:
    clusters:
      main:
        # Enable Istio components
        istio_enabled: true
        istio_enable_tracing: true
        kiali_enabled: true
        jaeger_enabled: true
        
        # Certificate configuration options
        acm_certificate_arn: "${output.acm.certificate_arns.main_wildcard}"
        
        # RECOMMENDED: Use External Secrets for certificate management
        use_external_secrets: true
        secrets_manager_secret_path: "certificates/wildcard-example.com-cert"
```

The Istio implementation will:

1. Deploy all necessary CRDs with `istio-base`
2. Set up the Istio control plane with `istiod`
3. Create an AWS Network Load Balancer with the Istio ingress gateway
4. Configure observability tools (Kiali and Jaeger)
5. Create the necessary IAM roles for AWS integration
6. Apply TLS certificates for secure traffic

For detailed information on Istio architecture, configuration options, and operational guidance, see the [Istio Service Mesh Guide](../../../docs/istio-service-mesh-guide.md).

#### Certificate Management - Important Changes

⚠️ **Important**: The preferred method for certificate management is now using the External Secrets Operator (separate component).

Due to AWS limitations, ACM private keys and certificates cannot be accessed via the API. To make certificate management more reliable, we've made these changes:

1. **New `external-secrets` Component**:
   - Deploy this component before `eks-addons`
   - Handles secure retrieval of certificates from AWS Secrets Manager
   - Manages certificate rotation automatically

2. **ACM Output Changes**:
   - `certificate_keys` and `certificate_crts` now return placeholder values
   - These fields cannot be used directly - they serve as documentation only
   - Use the scripts in `/scripts/certificates` to export and store certificates

3. **Certificate Storage**:
   - Export certificates from ACM with the provided scripts
   - Store in AWS Secrets Manager or SSM Parameter Store
   - Configure External Secrets to manage the Kubernetes TLS secrets

4. **Choose Appropriate Option**:
   - **External Secrets** (Recommended): Set `use_external_secrets: true`
   - **Direct Injection** (Legacy): Only for backward compatibility, requires manual export of certificates

#### Certificate Management Options Comparison

| Feature | External Secrets (Recommended) | Direct Injection (Legacy) |
|---------|--------------------------------|---------------------------|
| **Certificate Rotation** | Automatic | Manual |
| **Implementation Complexity** | Higher (requires additional component) | Lower (all-in-one) |
| **Security** | Better (keys managed by AWS) | Lower (keys in Terraform state) |
| **Dependencies** | External Secrets Operator | None |
| **Maintenance** | Low (automatic) | High (manual rotation) |
| **Setup** | `use_external_secrets: true` | Set `acm_certificate_crt` and `acm_certificate_key` directly |

##### External Secrets Approach

```yaml
# First deploy external-secrets component
external-secrets:
  vars:
    enabled: true
    # Configuration for External Secrets Operator

# Then configure eks-addons to use it
eks-addons:
  vars:
    clusters:
      main:
        use_external_secrets: true
        secrets_manager_secret_path: "certificates/wildcard-example-com"
        acm_certificate_arn: "${output.acm.certificate_arns.main_wildcard}"
```

##### Legacy Direct Injection Approach

```yaml
eks-addons:
  vars:
    clusters:
      main:
        use_external_secrets: false
        acm_certificate_arn: "${output.acm.certificate_arns.main_wildcard}"
        acm_certificate_crt: "${file:///tmp/example-com.crt}" # Manually exported from ACM
        acm_certificate_key: "${file:///tmp/example-com.key}" # Manually exported from ACM
```

For more information on Istio configuration and usage, see the [Istio Service Mesh Guide](../../../docs/istio-service-mesh-guide.md).

### Multiple Kubernetes Manifest Formats

The component supports multiple formats for defining Kubernetes manifests:

1. **JSON Object Format** (using `manifest`):
```yaml
kubernetes_manifests:
  namespace-example:
    enabled: true
    manifest: {
      "apiVersion": "v1",
      "kind": "Namespace",
      "metadata": {
        "name": "example"
      }
    }
```

2. **YAML String Format** (using `manifest_yaml`):
```yaml
kubernetes_manifests:
  ingress-example:
    enabled: true
    manifest_yaml: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: example-ingress
        namespace: default
      spec:
        rules:
        - host: example.com
          http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: example-service
                  port:
                    number: 80
```

3. **File Reference** (using `manifest_file`):
```yaml
kubernetes_manifests:
  cert-manager-issuers:
    enabled: true
    manifest_file: "components/terraform/eks-addons/kubernetes_manifests/cert-manager-issuers.yaml"
```

## IAM Integration

For addons that need to interact with AWS services, you can create a service account with an IAM role:

```yaml
eks-addons:
  vars:
    clusters:
      main:
        helm_releases:
          external-dns:
            create_service_account_role: true
            service_account_policy: "${file:/components/terraform/eks-addons/policies/external-dns-policy.json}"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | string | n/a | yes |
| enabled | Whether to create the resources | bool | `true` | no |
| assume_role_arn | ARN of the IAM role to assume | string | `""` | no |
| clusters | Map of EKS cluster configurations | map(object) | `{}` | yes |
| tags | Additional tags | map(string) | `{}` | no |
| default_tags | Default tags to apply to all resources | map(string) | `{}` | no |

### Legacy/Deprecated Inputs

The following inputs are deprecated and will be removed in a future version. Use the `clusters` map instead.

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | EKS cluster name (deprecated) | string | `""` | no |
| host | EKS cluster endpoint (deprecated) | string | `""` | no |
| cluster_ca_certificate | EKS cluster CA certificate (deprecated) | string | `""` | no |
| oidc_provider_arn | EKS OIDC provider ARN (deprecated) | string | `""` | no |
| use_external_secrets | Whether to use External Secrets Operator (deprecated) | bool | `false` | no |
| domain_name | Domain name for certificate setup (deprecated) | string | `"example.com"` | no |
| acm_certificate_arn | ARN of the ACM certificate (deprecated) | string | `""` | no |
| acm_certificate_crt | Certificate content (for direct injection) (deprecated) | string | `""` | no |
| acm_certificate_key | Certificate key (for direct injection) (deprecated) | string | `""` | no |
| secrets_manager_secret_path | Path to certificate in Secrets Manager (deprecated) | string | `""` | no |
| istio_enabled | Whether to enable Istio (deprecated) | bool | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| addon_arns | Map of EKS addon names to their ARNs |
| helm_release_statuses | Map of Helm release names to their status |
| kubernetes_manifest_names | Map of installed Kubernetes manifest names |
| service_account_role_arns | Map of IAM role ARNs for service accounts |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Addon installation fails | Required AWS API permissions missing | Ensure IAM permissions are properly configured |
| Certificate not available for Istio | ACM certificate not exported properly | Use the certificate export script and check secret content |
| Race conditions during deployment | Resources not ready when referenced | Add additional sleep resources or explicit dependencies |
| Istio gateway not receiving traffic | DNS records not created or NLB issues | Check external-dns logs and NLB configuration |
| IAM roles not properly assumed | OIDC provider misconfiguration | Verify OIDC provider URL and ARN are correct |

### Useful Commands

```bash
# Check EKS addon status
aws eks describe-addon --cluster-name <cluster-name> --addon-name <addon-name>

# Check Helm release status
kubectl get helmreleases -A

# Verify secrets for Istio
kubectl get secret -n istio-ingress istio-gateway-cert -o yaml

# Check service account IAM role configuration
kubectl describe serviceaccount -n <namespace> <service-account-name>
```