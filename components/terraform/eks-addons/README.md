# EKS Addons Component

_Last Updated: February 28, 2025_

## Overview

The EKS Addons component provides a secure, flexible, and error-resistant way to deploy and manage AWS EKS addons, Helm charts, and Kubernetes manifests across multiple EKS clusters. It enables comprehensive cluster enhancement with support for advanced autoscaling, monitoring, observability, certificate management, and service mesh capabilities.

Key features include:

- Multi-cluster management from a single deployment
- AWS EKS native addons integration with proper IAM permissions
- Helm chart deployment with customizable values
- Kubernetes manifest application with proper sequencing
- Advanced autoscaling with Karpenter and KEDA
- Service mesh integration with Istio
- Certificate management with ACM and External Secrets
- IAM role creation for service accounts (IRSA)
- Comprehensive validation and error prevention

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      EKS Addons Component                    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Multiple Clusters                          │
│                                                                   │
│  ┌─────────────┐     ┌─────────────┐      ┌─────────────┐         │
│  │  Cluster 1  │     │  Cluster 2  │      │  Cluster N  │         │
│  └──────┬──────┘     └──────┬──────┘      └──────┬──────┘         │
│         │                   │                    │                 │
│         ▼                   ▼                    ▼                 │
│  ┌──────────────────────────────────────────────────────────┐     │
│  │                   Resource Types                          │     │
│  │                                                           │     │
│  │  ┌──────────┐    ┌───────────┐    ┌────────────────┐     │     │
│  │  │ EKS      │    │ Helm      │    │ Kubernetes     │     │     │
│  │  │ Addons   │    │ Charts    │    │ Manifests      │     │     │
│  │  └────┬─────┘    └─────┬─────┘    └────────┬───────┘     │     │
│  └───────┼───────────────┼────────────────────┼─────────────┘     │
│          │               │                    │                   │
│          ▼               ▼                    ▼                   │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │                 Integrated Components                    │     │
│  │                                                          │     │
│  │  ┌──────────┐   ┌───────────┐   ┌──────────┐            │     │
│  │  │ IAM      │   │ External  │   │ Service  │            │     │
│  │  │ Roles    │   │ Secrets   │   │ Mesh     │            │     │
│  │  └──────────┘   └───────────┘   └──────────┘            │     │
│  └─────────────────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────────────────┘
```

The component is designed with a multi-cluster architecture to support:

1. **Multiple Clusters**: Configure and manage multiple EKS clusters concurrently
2. **Multiple Resource Types**:
   - AWS EKS native addons (managed by AWS)
   - Helm charts for extended functionality
   - Kubernetes manifests for custom resources
3. **Integration Features**:
   - IAM roles for service accounts (IRSA)
   - Certificate management
   - Service mesh configuration
   - Advanced autoscaling

The component handles installation sequencing with explicit wait periods to prevent race conditions and ensure proper dependency resolution between resources.

## Usage

### Basic Configuration

```yaml
eks-addons:
  vars:
    enabled: true
    region: "us-west-2"
    
    clusters:
      main:
        cluster_name: "testenv-01-main"
        kubernetes_host: ${output.eks.cluster_endpoint}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificate}
        oidc_provider_arn: ${output.eks.oidc_provider_arn}
        oidc_provider_url: ${output.eks.oidc_provider_url}
        
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
            manifest:
              apiVersion: "v1"
              kind: "Namespace"
              metadata:
                name: "dev"
```

### Multi-Cluster Configuration

```yaml
eks-addons:
  vars:
    region: "us-west-2"
    
    clusters:
      dev:
        cluster_name: "testenv-01-dev"
        kubernetes_host: ${output.eks.cluster_endpoints.dev}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificates.dev}
        oidc_provider_arn: ${output.eks.oidc_provider_arns.dev}
        oidc_provider_url: ${output.eks.oidc_provider_urls.dev}
        
        # Development cluster addons
        addons:
          vpc-cni:
            name: "vpc-cni"
            version: "v1.13.4-eksbuild.1"
          
        helm_releases:
          metrics-server:
            enabled: true
            chart: "metrics-server"
            chart_version: "3.10.0"
            
      prod:
        cluster_name: "testenv-01-prod"
        kubernetes_host: ${output.eks.cluster_endpoints.prod}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificates.prod}
        oidc_provider_arn: ${output.eks.oidc_provider_arns.prod}
        oidc_provider_url: ${output.eks.oidc_provider_urls.prod}
        
        # Production cluster addons with more components
        addons:
          vpc-cni:
            name: "vpc-cni"
            version: "v1.13.4-eksbuild.1"
          
          aws-guardduty-agent:
            name: "aws-guardduty-agent"
            version: "v1.5.0-eksbuild.1"
        
        helm_releases:
          metrics-server:
            enabled: true
            chart: "metrics-server"
            chart_version: "3.10.0"
            
          prometheus:
            enabled: true
            chart: "kube-prometheus-stack"
            repository: "https://prometheus-community.github.io/helm-charts"
            chart_version: "48.3.1"
            namespace: "monitoring"
            create_namespace: true
```

### Advanced Autoscaling with Karpenter and KEDA

```yaml
eks-addons:
  vars:
    clusters:
      main:
        # Cluster connection details...
        
        # Enable Karpenter for node autoscaling
        helm_releases:
          karpenter:
            enabled: true
            chart: "karpenter"
            repository: "oci://public.ecr.aws/karpenter/karpenter"
            chart_version: "v0.32.1"
            namespace: "karpenter"
            create_namespace: true
            set_values:
              serviceAccount.create: true
              serviceAccount.name: "karpenter"
              settings.aws.clusterName: "testenv-01-main"
              settings.aws.clusterEndpoint: ${output.eks.cluster_endpoints.main}
              settings.aws.defaultInstanceProfile: "testenv-01-karpenter-node-profile"
            create_service_account_role: true
            service_account_policy: "${file:/components/terraform/eks-addons/policies/karpenter-policy.json}"
          
          # Enable KEDA for pod autoscaling based on event sources
          keda:
            enabled: true
            chart: "keda"
            repository: "https://kedacore.github.io/charts"
            chart_version: "2.12.0"
            namespace: "keda"
            create_namespace: true
            set_values:
              serviceAccount.create: true
              serviceAccount.name: "keda-operator"
            create_service_account_role: true
            service_account_policy: "${file:/components/terraform/eks-addons/policies/keda-policy.json}"
```

### Service Mesh with Istio Integration

```yaml
eks-addons:
  vars:
    domain_name: "example.com"  # Domain for Istio gateway
    
    clusters:
      main:
        # Cluster connection details...
        
        helm_releases:
          # Istio base installation
          istio-base:
            enabled: true
            chart: "base"
            repository: "https://istio-release.storage.googleapis.com/charts"
            chart_version: "1.18.2"
            namespace: "istio-system"
            create_namespace: true
          
          # Istio control plane
          istiod:
            enabled: true
            chart: "istiod"
            repository: "https://istio-release.storage.googleapis.com/charts"
            chart_version: "1.18.2"
            namespace: "istio-system"
            set_values:
              pilot.resources.requests.memory: "512Mi"
              pilot.resources.requests.cpu: "500m"
              global.tracer.zipkin.address: "jaeger-collector.istio-system:9411"
            depends_on:
              - istio-base
          
          # Istio ingress gateway
          istio-ingress:
            enabled: true
            chart: "gateway"
            repository: "https://istio-release.storage.googleapis.com/charts"
            chart_version: "1.18.2"
            namespace: "istio-ingress"
            create_namespace: true
            set_values:
              service.type: "LoadBalancer"
              autoscaling.enabled: true
              autoscaling.minReplicas: 2
              autoscaling.maxReplicas: 5
            depends_on:
              - istiod
        
        # Certificate management for Istio
        use_external_secrets: true
        secrets_manager_secret_path: "certificates/wildcard-example-com"
```

### Certificate Management Options

For secure certificate management with Istio, the component offers two approaches:

#### External Secrets Approach (Recommended)

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
        # Cluster connection details...
        
        # Certificate configuration
        use_external_secrets: true
        secrets_manager_secret_path: "certificates/wildcard-example-com"
        acm_certificate_arn: "${output.acm.certificate_arns.main_wildcard}"
```

#### Legacy Direct Injection Approach

```yaml
eks-addons:
  vars:
    clusters:
      main:
        # Cluster connection details...
        
        # Direct certificate configuration
        use_external_secrets: false
        acm_certificate_arn: "${output.acm.certificate_arns.main_wildcard}"
        acm_certificate_crt: "${file:///tmp/example-com.crt}" # Manually exported from ACM
        acm_certificate_key: "${file:///tmp/example-com.key}" # Manually exported from ACM
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | string | - | yes |
| assume_role_arn | ARN of the IAM role to assume | string | null | no |
| default_tags | Default tags to apply to all resources | map(string) | {} | no |
| clusters | Map of cluster configurations with addons, Helm releases, and Kubernetes manifests | map(object) | {} | yes |
| tags | Common tags to apply to all resources | map(string) | {} | no |
| domain_name | Domain name for certificates and DNS records | string | "example.com" | no |
| istio_enabled | Whether to enable Istio service mesh (deprecated) | bool | false | no |
| istio_enable_tracing | Whether to enable distributed tracing in Istio (deprecated) | bool | true | no |
| istio_gateway_min_replicas | Minimum replicas for Istio gateway (deprecated) | number | 2 | no |
| istio_gateway_max_replicas | Maximum replicas for Istio gateway (deprecated) | number | 5 | no |
| kiali_enabled | Whether to enable Kiali visualization for Istio (deprecated) | bool | false | no |
| jaeger_enabled | Whether to enable Jaeger tracing for Istio (deprecated) | bool | false | no |
| jaeger_storage_type | Storage type for Jaeger (memory, elasticsearch, cassandra) (deprecated) | string | "memory" | no |
| acm_certificate_arn | ARN of the ACM certificate to use for Istio gateway | string | "" | no |
| acm_certificate_crt | Certificate content from ACM | string | "" | no |
| acm_certificate_key | Private key content from ACM | string | "" | no |
| secrets_manager_secret_path | Path to the secret in AWS Secrets Manager containing the TLS certificate | string | "" | no |
| use_external_secrets | Whether to use external-secrets operator to retrieve certificates from Secrets Manager | bool | true | no |

### Cluster Configuration Object

The `clusters` variable accepts a map of cluster configurations with the following structure:

```yaml
clusters:
  cluster_name:
    # Required fields
    cluster_name: string             # EKS cluster name
    kubernetes_host: string          # EKS cluster endpoint URL
    cluster_ca_certificate: string   # Base64-encoded cluster CA certificate
    oidc_provider_arn: string        # ARN of the OIDC provider
    oidc_provider_url: string        # URL of the OIDC provider
    
    # Optional fields
    service_account_token_path: string   # Path to service account token
    
    # Feature flags
    enable_aws_load_balancer_controller: bool   # Default: true
    enable_cluster_autoscaler: bool             # Default: true
    enable_external_dns: bool                   # Default: true
    enable_cert_manager: bool                   # Default: true
    enable_metrics_server: bool                 # Default: true
    enable_aws_for_fluentbit: bool              # Default: false
    enable_aws_cloudwatch_metrics: bool         # Default: false
    enable_karpenter: bool                      # Default: false
    enable_keda: bool                           # Default: false
    enable_istio: bool                          # Default: false
    enable_external_secrets: bool               # Default: false
    
    # Configuration options
    cert_manager_letsencrypt_email: string             # Required if cert_manager is enabled
    external_dns_domain_filters: list(string)          # Default: []
    karpenter_provisioner_config: map(any)             # Default: {}
    fluentbit_log_group_name: string                   # Optional
    log_retention_days: number                         # Default: 90
    istio_config: map(any)                             # Default: {}
    additional_namespaces: list(string)                # Default: []
    
    # AWS EKS Addons
    addons: map(object)
    
    # Helm releases
    helm_releases: map(object)
    
    # Kubernetes manifests
    kubernetes_manifests: map(object)
    
    # Tags
    tags: map(string)                                  # Default: {}
```

## Outputs

| Name | Description |
|------|-------------|
| addon_arns | Map of addon names to addon ARNs |
| helm_release_statuses | Map of Helm release names to statuses |
| service_account_role_arns | Map of service account names to role ARNs |

## Troubleshooting

### Common Issues

| Issue | Possible Causes | Solution |
|-------|----------------|----------|
| Addon installation fails | Missing IAM permissions, version constraints | Check IAM role permissions, verify addon version compatibility |
| Helm chart fails to install | Chart repository issues, validation errors | Verify repository URL, check values for required fields |
| Certificate errors with Istio | Missing or incorrect certificate data | Check secrets_manager_secret_path or direct certificate values |
| IAM role not assuming correctly | OIDC provider misconfiguration | Verify OIDC provider URL and ARN are correct |
| Resources created in wrong order | Dependency chains not specified | Add appropriate depends_on settings in helm_releases |
| External Secrets not syncing | Missing permissions or incorrect path | Check IAM permissions and secrets_manager_secret_path |
| Karpenter not scaling nodes | Instance profile issues | Verify AWS instance profile exists and permissions are correct |

### Debugging Commands

```bash
# Check EKS addon status
aws eks describe-addon --cluster-name <cluster-name> --addon-name <addon-name>

# Check Helm release status
kubectl get helmreleases -A
helm list -n kube-system

# Verify Istio certificate
kubectl get secret -n istio-ingress istio-gateway-cert -o yaml

# Check ExternalSecret status
kubectl get externalsecret -n istio-ingress
kubectl describe externalsecret istio-certificate -n istio-ingress

# Verify service account IAM configuration
kubectl describe serviceaccount -n kube-system aws-load-balancer-controller

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller
```

## Related Resources

- [EKS Addons Reference Guide](/docs/eks-addons-reference.md)
- [Istio Service Mesh Guide](/docs/istio-service-mesh-guide.md)
- [EKS Autoscaling Guide](/docs/eks-autoscaling-guide.md)
- [EKS Autoscaling Architecture](/docs/diagrams/eks-autoscaling-architecture.md)
- [External Secrets Component](/components/terraform/external-secrets/README.md)
- [ACM Component](/components/terraform/acm/README.md)