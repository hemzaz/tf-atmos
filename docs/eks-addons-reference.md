# EKS Addons Reference Guide

_Last Updated: February 28, 2025_

This document provides a comprehensive reference for the AWS EKS addons implemented in this framework. It covers both AWS native EKS addons and Helm-deployed extensions that enhance the functionality of Kubernetes clusters.

## 1. AWS Native EKS Addons

AWS EKS provides several native addons that are integrated with the EKS control plane. These addons are managed by AWS and provide core functionality for Kubernetes clusters.

| Addon | Description | IAM Required | Version |
|-------|-------------|--------------|---------|
| `vpc-cni` | Amazon VPC CNI for pod networking | Yes (built-in) | v1.13.4-eksbuild.1 |
| `coredns` | Kubernetes DNS service | No | v1.10.1-eksbuild.1 |
| `kube-proxy` | Kubernetes network proxy | No | v1.28.2-eksbuild.1 |
| `aws-ebs-csi-driver` | EBS storage for persistent volumes | Yes | v1.24.0-eksbuild.1 |
| `aws-efs-csi-driver` | EFS storage for persistent volumes | Yes | v1.7.0-eksbuild.1 |
| `aws-fsx-csi-driver` | FSx storage for persistent volumes | Yes | v1.7.0-eksbuild.1 |
| `adot` | AWS Distro for OpenTelemetry | Yes | v0.90.0-eksbuild.1 |
| `aws-cloudwatch-metrics` | CloudWatch metrics collection | Yes | v1.1.1-eksbuild.1 |
| `aws-for-fluentbit` | Container logging to CloudWatch | Yes | v2.35.0-eksbuild.1 |
| `aws-guardduty-agent` | GuardDuty agent for runtime threat detection | No | v1.5.0-eksbuild.1 |
| `aws-gateway-api-controller` | API gateway management | Yes | v1.0.2-eksbuild.1 |
| `aws-node-termination-handler` | Graceful handling of EC2 terminations | Yes | v1.19.0-eksbuild.1 |
| `aws-privateca-issuer` | Private certificate management | Yes | v1.2.2-eksbuild.1 |
| `bottlerocket` | Bottlerocket AMI for EKS nodes | No | v1.0.0-eksbuild.1 |
| `secrets-store-csi-driver-provider-aws` | Secret mounting from AWS Secrets Manager | Yes | v1.1.0-eksbuild.1 |

### Amazon VPC CNI (vpc-cni)

The Amazon VPC CNI plugin for Kubernetes enables native VPC networking for Kubernetes pods.

**Key Features:**
- Assigns an IP address from the VPC to each pod
- Provides high throughput and low latency networking
- Supports security groups for pods
- Native integration with AWS VPC networking

**Configuration Example:**
```yaml
vpc-cni:
  name: "vpc-cni"
  version: "v1.13.4-eksbuild.1"
  resolve_conflicts: "OVERWRITE"
```

### CoreDNS

CoreDNS is a flexible, extensible DNS server that serves as Kubernetes' cluster DNS.

**Key Features:**
- Provides DNS records for Kubernetes services
- Supports service discovery in the cluster
- Configurable through CoreFile for advanced use cases
- Integrated with Kubernetes API

**Configuration Example:**
```yaml
coredns:
  name: "coredns"
  version: "v1.10.1-eksbuild.1"
```

### Kube-proxy

Kube-proxy maintains network rules on nodes to allow communication to Kubernetes pods.

**Key Features:**
- Implements part of the Kubernetes Service concept
- Manages iptables rules to route traffic to the appropriate pods
- Handles load balancing for services

**Configuration Example:**
```yaml
kube-proxy:
  name: "kube-proxy"
  version: "v1.28.2-eksbuild.1"
```

### AWS EBS CSI Driver

The Amazon EBS CSI Driver allows Kubernetes to use EBS volumes for persistent storage.

**Key Features:**
- Dynamic provisioning of EBS volumes
- Volume snapshots and restoration
- Volume resizing
- Support for different volume types (gp2, gp3, io1, etc.)

**IAM Permissions Required:**
- EC2 permissions to create, attach, and manage EBS volumes
- Tagging permissions for volumes and snapshots

**Configuration Example:**
```yaml
aws-ebs-csi-driver:
  name: "aws-ebs-csi-driver"
  version: "v1.24.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-ebs-csi-driver-policy.json}"
```

### AWS Distro for OpenTelemetry (ADOT)

ADOT provides a secure, production-ready distribution of the OpenTelemetry project with integration for AWS monitoring services.

**Key Features:**
- Collects metrics, traces, and logs
- Exports telemetry data to AWS services like CloudWatch, X-Ray
- Compatible with OpenTelemetry standard
- Support for multiple exporters and receivers

**IAM Permissions Required:**
- CloudWatch permissions for metrics
- X-Ray permissions for tracing
- CloudWatch Logs permissions for logs

**Configuration Example:**
```yaml
adot:
  name: "adot"
  version: "v0.90.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/adot-policy.json}"
```

### AWS GuardDuty Agent

The AWS GuardDuty agent integrates with Amazon GuardDuty to provide runtime threat detection for EKS clusters.

**Key Features:**
- Detects potential security threats at runtime
- Identifies malicious or suspicious behavior in containers
- Integrates with AWS GuardDuty security service
- Minimal performance impact

**Configuration Example:**
```yaml
aws-guardduty-agent:
  name: "aws-guardduty-agent"
  version: "v1.5.0-eksbuild.1"
```

### AWS EFS CSI Driver

The Amazon EFS CSI Driver allows Kubernetes to use EFS file systems for persistent storage.

**Key Features:**
- Dynamic provisioning of EFS file systems
- Support for ReadWriteMany access mode
- Multiple pods can share the same storage across nodes
- Persistent storage that survives pod and node terminations

**IAM Permissions Required:**
- EFS permissions to create, mount, and manage access points
- EC2 permissions to describe availability zones

**Configuration Example:**
```yaml
aws-efs-csi-driver:
  name: "aws-efs-csi-driver"
  version: "v1.7.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-efs-csi-driver-policy.json}"
```

### AWS FSx CSI Driver

The Amazon FSx CSI Driver allows Kubernetes to use FSx for Lustre and FSx for Windows File Server in Kubernetes.

**Key Features:**
- Dynamic provisioning of FSx volumes
- Support for FSx for Lustre and Windows File Server
- High-performance file storage
- Persistent storage between pod lifecycles

**IAM Permissions Required:**
- FSx permissions to create and manage file systems
- EC2 permissions to describe resources

**Configuration Example:**
```yaml
aws-fsx-csi-driver:
  name: "aws-fsx-csi-driver"
  version: "v1.7.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-fsx-csi-driver-policy.json}"
```

### AWS CloudWatch Metrics

The AWS CloudWatch Metrics addon collects and sends container metrics to CloudWatch.

**Key Features:**
- Collects Kubernetes metrics
- Forwards metrics to CloudWatch
- Supports auto-scaling based on metrics
- Provides operational visibility

**IAM Permissions Required:**
- CloudWatch permissions to publish metrics
- EC2 permissions to describe resources

**Configuration Example:**
```yaml
aws-cloudwatch-metrics:
  name: "aws-cloudwatch-metrics"
  version: "v1.1.1-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-cloudwatch-metrics-policy.json}"
```

### AWS for Fluentbit

The AWS for Fluentbit addon streams container logs to CloudWatch Logs, Amazon S3, or Amazon Kinesis.

**Key Features:**
- Collects container logs
- Forwards logs to CloudWatch Logs, S3, or Kinesis
- Lightweight and efficient
- Configurable filtering and routing

**IAM Permissions Required:**
- CloudWatch Logs permissions to create and write to log groups
- Optional S3/Kinesis permissions

**Configuration Example:**
```yaml
aws-for-fluentbit:
  name: "aws-for-fluentbit"
  version: "v2.35.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-for-fluentbit-policy.json}"
```

### AWS Gateway API Controller

The AWS Gateway API Controller integrates Kubernetes Gateway API with AWS API Gateway and Application Load Balancers.

**Key Features:**
- Provides Gateway API implementation for Kubernetes
- Integrates with API Gateway for routing and management
- Supports multiple protocols and advanced routing
- Enhanced API traffic management

**IAM Permissions Required:**
- API Gateway permissions for CRUD operations
- ELB permissions for load balancer management

**Configuration Example:**
```yaml
aws-gateway-api-controller:
  name: "aws-gateway-api-controller"
  version: "v1.0.2-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-gateway-api-controller-policy.json}"
```

### AWS Node Termination Handler

The AWS Node Termination Handler ensures graceful handling of EC2 instance terminations and maintenance events.

**Key Features:**
- Captures EC2 Spot Instance interruption notices
- Handles EC2 maintenance events
- Facilitates graceful pod termination
- Integrates with Auto Scaling Group lifecycle hooks

**IAM Permissions Required:**
- EC2 permissions to describe instances
- AutoScaling permissions for lifecycle hooks
- SQS permissions for queue management

**Configuration Example:**
```yaml
aws-node-termination-handler:
  name: "aws-node-termination-handler"
  version: "v1.19.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-node-termination-handler-policy.json}"
```

### AWS Private CA Issuer

The AWS Private CA Issuer enables certificate management for Kubernetes using AWS Private Certificate Authority.

**Key Features:**
- Integration with AWS Private Certificate Authority
- Automated certificate provisioning and renewal
- Kubernetes cert-manager integration
- Centralized certificate management

**IAM Permissions Required:**
- ACM-PCA permissions for certificate operations

**Configuration Example:**
```yaml
aws-privateca-issuer:
  name: "aws-privateca-issuer"
  version: "v1.2.2-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/aws-private-ca-issuer-policy.json}"
```

### Bottlerocket

The Bottlerocket addon provides integration for Bottlerocket-based EKS nodes.

**Key Features:**
- Optimized for container workloads
- Minimal OS footprint
- Automated updates
- Enhanced security posture

**Configuration Example:**
```yaml
bottlerocket:
  name: "bottlerocket-shadow"
  version: "v1.0.0-eksbuild.1"
```

### Secrets Store CSI Driver Provider AWS

The AWS Secrets Manager CSI Driver allows mounting AWS Secrets Manager secrets as volumes in pods.

**Key Features:**
- Mount secrets as files in pods
- Automatic secret rotation
- Integration with AWS Secrets Manager and SSM
- Secure access to credentials

**IAM Permissions Required:**
- Secrets Manager permissions to read secrets
- SSM permissions to read parameters
- KMS permissions for decryption

**Configuration Example:**
```yaml
secrets-store-csi-driver-provider-aws:
  name: "aws-secrets-manager-csi-driver"
  version: "v1.1.0-eksbuild.1"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/secrets-store-csi-driver-provider-aws-policy.json}"
```

## 2. Helm-deployed Addons

In addition to the AWS native addons, this framework provides several additional components deployed via Helm charts.

| Component | Description | IAM Required | Chart Version |
|-----------|-------------|--------------|--------------|
| `metrics-server` | Kubernetes resource metrics | No | 3.10.0 |
| `prometheus` | Monitoring and alerting | No | 48.3.1 |
| `aws-load-balancer-controller` | ALB/NLB integration | Yes | 1.6.1 |
| `karpenter` | Node autoscaling | Yes | v0.32.1 |
| `keda` | Pod autoscaling | Yes | 2.12.0 |
| `cluster-autoscaler` | Node group autoscaling | Yes | 9.29.1 |
| `vertical-pod-autoscaler` | Resource request autoscaling | No | 1.4.0 |
| `cluster-proportional-autoscaler` | Replicas based on cluster size | No | 1.1.0 |
| `cert-manager` | Certificate management | No | v1.13.2 |
| `External DNS` | DNS record management | Yes | 1.13.1 |
| `External Secrets` | External secret management | Yes | 0.9.9 |
| `ingress-nginx` | NGINX Ingress Controller | No | 4.8.3 |
| `opa-gatekeeper` | Policy enforcement | No | 3.14.0 |
| `velero` | Backup and restore | Yes | 5.1.4 |
| `argocd` | GitOps continuous delivery | No | 5.51.4 |
| `argo-workflows` | Workflow automation | No | 0.39.0 |
| `argo-events` | Event-driven workflows | No | 2.4.0 |
| `argo-rollouts` | Progressive delivery | No | 2.32.5 |

### Metrics Server

Metrics Server collects resource metrics from kubelets and provides them through the Kubernetes Metrics API.

**Key Features:**
- Lightweight short-term metrics storage
- Resource metrics (CPU/memory) for Horizontal Pod Autoscaler
- Used by the Kubernetes autoscaler
- No persistent storage

**Configuration Example:**
```yaml
metrics-server:
  enabled: true
  chart: "metrics-server"
  repository: "https://kubernetes-sigs.github.io/metrics-server/"
  chart_version: "3.10.0"
  namespace: "kube-system"
  set_values:
    apiService.create: true
    args:
      - "--kubelet-preferred-address-types=InternalIP"
```

### Prometheus Stack

The Prometheus stack includes Prometheus, Alertmanager, and Grafana for complete monitoring solution.

**Key Features:**
- Time-series metric collection and storage
- Powerful query language (PromQL)
- Alerting capabilities
- Grafana dashboards for visualization

**Configuration Example:**
```yaml
prometheus:
  enabled: true
  chart: "kube-prometheus-stack"
  repository: "https://prometheus-community.github.io/helm-charts"
  chart_version: "48.3.1"
  namespace: "monitoring"
  create_namespace: true
  values:
    - |
      grafana:
        enabled: true
        adminPassword: "${ssm:/testenv-01/grafana/admin-password}"
      prometheus:
        prometheusSpec:
          retention: 15d
          resources:
            requests:
              memory: 1Gi
              cpu: 500m
            limits:
              memory: 2Gi
```

### AWS Load Balancer Controller

The AWS Load Balancer Controller manages AWS Application Load Balancers and Network Load Balancers for Kubernetes services.

**Key Features:**
- Automatically provisions ALBs and NLBs for Kubernetes services
- Supports Ingress and Service resources
- Target group binding for direct integrations
- Advanced routing capabilities

**IAM Permissions Required:**
- EC2 permissions to describe resources
- Elasticloadbalancing permissions for ALB/NLB management

**Configuration Example:**
```yaml
aws-load-balancer-controller:
  enabled: true
  chart: "aws-load-balancer-controller"
  repository: "https://aws.github.io/eks-charts"
  chart_version: "1.6.1"
  namespace: "kube-system"
  set_values:
    clusterName: "testenv-01-main"
    serviceAccount.create: true
    serviceAccount.name: "aws-load-balancer-controller"
  create_service_account_role: true
  service_account_policy: "..."
```

## 3. Autoscaling Addons

### Karpenter

Karpenter is a node autoscaler that provisions right-sized compute resources in response to workload requirements.

**Key Features:**
- Just-in-time node provisioning
- Diverse instance type support
- Fast node startup (typically under 60 seconds)
- Bin-packing and consolidation
- Spot instance support

**IAM Permissions Required:**
- EC2 permissions to create and manage instances
- IAM permissions for instance profiles

**Configuration Example:**
```yaml
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
```

### KEDA

KEDA is a Kubernetes Event-driven Autoscaler for pod-based autoscaling based on external metrics and events.

**Key Features:**
- Event-driven autoscaling
- Support for 40+ event sources
- Scaling to zero capability
- Native Kubernetes integration

**IAM Permissions Required:**
- Depends on the scalers used (SQS, CloudWatch, DynamoDB, etc.)

**Configuration Example:**
```yaml
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

### Cluster Autoscaler

Cluster Autoscaler automatically adjusts the size of Kubernetes clusters based on pod scheduling demand and resource constraints.

**Key Features:**
- Automatically scales node groups based on pending pods
- Works with Auto Scaling Groups
- Supports scale-up and scale-down operations
- Respects pod disruption budgets during scale-down

**IAM Permissions Required:**
- AutoScaling permissions to modify ASG capacity
- EC2 permissions to describe instances and templates

**Configuration Example:**
```yaml
cluster-autoscaler:
  enabled: true
  chart: "cluster-autoscaler"
  repository: "https://kubernetes.github.io/autoscaler"
  chart_version: "9.29.1"
  namespace: "kube-system"
  set_values:
    autoDiscovery.clusterName: "testenv-01-main"
    awsRegion: "eu-west-2"
    extraArgs.balance-similar-node-groups: true
    extraArgs.expander: least-waste
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/cluster-autoscaler-policy.json}"
```

### Vertical Pod Autoscaler

Vertical Pod Autoscaler automatically adjusts CPU and memory resource requests for pods based on their usage.

**Key Features:**
- Automatically sets resource requests
- Multiple modes (recommendation, auto, initial)
- Improves resource utilization
- Prevents out-of-memory errors

**Configuration Example:**
```yaml
vertical-pod-autoscaler:
  enabled: true
  chart: "vpa"
  repository: "https://charts.fairwinds.com/stable"
  chart_version: "1.4.0"
  namespace: "vpa"
  create_namespace: true
```

### Cluster Proportional Autoscaler

Cluster Proportional Autoscaler automatically scales the number of replicas of a service proportionally to the size of the cluster.

**Key Features:**
- Scales services based on node count
- Linear or step-based scaling
- Ideal for cluster-wide services
- Low resource overhead

**Configuration Example:**
```yaml
cluster-proportional-autoscaler:
  enabled: true
  chart: "cluster-proportional-autoscaler"
  repository: "https://kubernetes-sigs.github.io/cluster-proportional-autoscaler"
  chart_version: "1.1.0"
  namespace: "kube-system"
```

### Cert Manager

Cert Manager automates the management and issuance of TLS certificates from various sources.

**Key Features:**
- Automated certificate issuance and renewal
- Support for multiple CAs (Let's Encrypt, Vault, etc.)
- Integration with various Ingress controllers
- Certificate rotation handling

**Configuration Example:**
```yaml
cert-manager:
  enabled: true
  chart: "cert-manager"
  repository: "https://charts.jetstack.io"
  chart_version: "v1.13.2"
  namespace: "cert-manager"
  create_namespace: true
  set_values:
    installCRDs: true
```

### External DNS

External DNS synchronizes exposed Kubernetes services and ingresses with DNS providers.

**Key Features:**
- Automatic DNS record creation
- Support for multiple DNS providers
- Source-of-truth synchronization
- Support for record annotations

**IAM Permissions Required:**
- Route53 permissions to manage records in hosted zones

**Configuration Example:**
```yaml
External DNS:
  enabled: true
  chart: "external-dns"
  repository: "https://kubernetes-sigs.github.io/external-dns"
  chart_version: "1.13.1"
  namespace: "external-dns"
  create_namespace: true
  set_values:
    provider: aws
    aws.region: "eu-west-2"
    domainFilters: ["example.com"]
    policy: "sync"
    registry: "txt"
    txtOwnerId: "testenv-01-main"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/external-dns-policy.json}"
```

### External Secrets

External Secrets synchronizes external secret management systems with Kubernetes secrets.

**Key Features:**
- Sync secrets from external sources
- Support for multiple providers (AWS, GCP, Azure, Vault)
- Automatic secret rotation
- Integration with existing secret management systems

**IAM Permissions Required:**
- Secrets Manager and SSM Parameter Store permissions

**Configuration Example:**
```yaml
External Secrets:
  enabled: true
  chart: "external-secrets"
  repository: "https://charts.external-secrets.io"
  chart_version: "0.9.9"
  namespace: "external-secrets"
  create_namespace: true
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/external-secrets-policy.json}"
```

### Ingress NGINX

Ingress NGINX provides an Ingress controller for Kubernetes using NGINX as a reverse proxy and load balancer.

**Key Features:**
- HTTP and HTTPS load balancing
- Path-based routing
- SSL/TLS termination
- Advanced traffic management

**Configuration Example:**
```yaml
ingress-nginx:
  enabled: true
  chart: "ingress-nginx"
  repository: "https://kubernetes.github.io/ingress-nginx"
  chart_version: "4.8.3"
  namespace: "ingress-nginx"
  create_namespace: true
  set_values:
    controller.service.type: LoadBalancer
    controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type": "nlb"
```

### OPA Gatekeeper

OPA Gatekeeper is a policy controller for Kubernetes that enforces configurable policies.

**Key Features:**
- Policy enforcement
- Custom admission control
- Audit capabilities
- Declarative policy management

**Configuration Example:**
```yaml
opa-gatekeeper:
  enabled: true
  chart: "gatekeeper"
  repository: "https://open-policy-agent.github.io/gatekeeper/charts"
  chart_version: "3.14.0"
  namespace: "gatekeeper-system"
  create_namespace: true
```

### Velero

Velero is a backup and disaster recovery solution for Kubernetes clusters.

**Key Features:**
- Cluster backup and restore
- Scheduled backups
- Disaster recovery
- Cluster migration

**IAM Permissions Required:**
- S3 permissions for backup storage
- EC2 permissions for volume snapshots

**Configuration Example:**
```yaml
velero:
  enabled: true
  chart: "velero"
  repository: "https://vmware-tanzu.github.io/helm-charts"
  chart_version: "5.1.4"
  namespace: "velero"
  create_namespace: true
  set_values:
    initContainers[0].name: "velero-plugin-for-aws"
    initContainers[0].image: "velero/velero-plugin-for-aws:v1.7.1"
    initContainers[0].volumeMounts[0].mountPath: "/target"
    initContainers[0].volumeMounts[0].name: "plugins"
    configuration.provider: "aws"
    configuration.backupStorageLocation.bucket: "testenv-01-velero-backup"
    configuration.backupStorageLocation.config.region: "eu-west-2"
  create_service_account_role: true
  service_account_policy: "${file:/components/terraform/eks-addons/policies/velero-policy.json}"
```

### Argo CD

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes.

**Key Features:**
- GitOps workflow implementation
- Automated deployment
- Application health monitoring
- Rollback capabilities

**Configuration Example:**
```yaml
argocd:
  enabled: true
  chart: "argo-cd"
  repository: "https://argoproj.github.io/argo-helm"
  chart_version: "5.51.4"
  namespace: "argocd"
  create_namespace: true
  values:
    - |
      server:
        extraArgs:
          - --insecure
        config:
          repositories: |
            - type: git
              url: https://github.com/argoproj/argocd-example-apps
```

### Argo Workflows

Argo Workflows is a container-native workflow engine for orchestrating parallel jobs on Kubernetes.

**Key Features:**
- Container-native workflows
- Parallel execution
- Complex dependency management
- Artifacts and parameters

**Configuration Example:**
```yaml
argo-workflows:
  enabled: true
  chart: "argo-workflows"
  repository: "https://argoproj.github.io/argo-helm"
  chart_version: "0.39.0"
  namespace: "argo"
  create_namespace: true
  set_values:
    controller.clusterWorkflowTemplates.enabled: true
    controller.workflowNamespaces: "argo,default"
```

### Argo Events

Argo Events is an event-driven workflow automation framework for Kubernetes.

**Key Features:**
- Event sources and triggers
- Integration with Argo Workflows
- Complex event processing
- Sensors and dependencies

**Configuration Example:**
```yaml
argo-events:
  enabled: true
  chart: "argo-events"
  repository: "https://argoproj.github.io/argo-helm"
  chart_version: "2.4.0"
  namespace: "argo-events"
  create_namespace: true
```

### Argo Rollouts

Argo Rollouts is a progressive delivery controller for Kubernetes.

**Key Features:**
- Advanced deployment strategies
- Blue-green deployments
- Canary deployments
- Automated analysis and promotion

**Configuration Example:**
```yaml
argo-rollouts:
  enabled: true
  chart: "argo-rollouts"
  repository: "https://argoproj.github.io/argo-helm"
  chart_version: "2.32.5"
  namespace: "argo-rollouts"
  create_namespace: true
  set_values:
    dashboard.enabled: true
```

## 4. Multi-Cluster Configuration

The EKS addons component in this framework supports managing multiple clusters from a single deployment. This is particularly useful for organizations with multiple EKS clusters that need consistent addon configurations.

### Multiple Clusters Design

The component uses a map-based configuration approach where each cluster can have its own set of addons, Helm releases, and Kubernetes manifests:

```yaml
eks-addons:
  vars:
    clusters:
      cluster1:
        cluster_name: "dev-cluster"
        kubernetes_host: ${output.eks.cluster_endpoints.dev}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificates.dev}
        oidc_provider_arn: ${output.eks.oidc_provider_arns.dev}
        oidc_provider_url: ${output.eks.oidc_provider_urls.dev}
        
        # Cluster-specific addons
        addons: 
          vpc-cni: {...}
          coredns: {...}
        
        # Cluster-specific Helm releases
        helm_releases:
          metrics-server: {...}
          
      cluster2:
        cluster_name: "prod-cluster"
        kubernetes_host: ${output.eks.cluster_endpoints.prod}
        cluster_ca_certificate: ${output.eks.cluster_ca_certificates.prod}
        oidc_provider_arn: ${output.eks.oidc_provider_arns.prod}
        oidc_provider_url: ${output.eks.oidc_provider_urls.prod}
        
        # Production-specific configuration
        addons: 
          vpc-cni: {...}
          coredns: {...}
          aws-guardduty-agent: {...}
        
        helm_releases:
          metrics-server: {...}
          prometheus: {...}
```

### Cross-Cluster Resource Sharing

When managing multiple clusters, consider these best practices:

1. **Centralized Certificate Management**: Use AWS ACM and Secrets Manager to create and distribute certificates across multiple clusters
2. **Consistent IAM Roles**: Use consistent naming patterns for IAM roles across clusters
3. **Environment-Specific Variables**: Use Atmos variable hierarchies to differentiate environment-specific settings
4. **Version Control**: Keep addon versions consistent across similar environments

### Cluster Configuration Priority

The component processes configurations in this order:

1. Cluster-specific settings from the `clusters` map
2. Global settings (if not overridden at the cluster level)
3. Legacy/deprecated single-cluster settings (for backward compatibility)

## 5. Implementation Best Practices

### Addon Version Management

- Always specify an explicit version for each addon
- Update versions incrementally, not skipping multiple versions
- Test addon updates in development environments before production
- Document any version-specific configuration requirements
- Consider using variables with centrally defined version numbers

### IAM Role Configuration

- Use dedicated IAM roles for each addon that requires AWS permissions
- Apply least privilege principle when defining IAM policies
- Use the `create_service_account_role` parameter to automatically create and configure IAM roles
- Store IAM policy documents in the `policies/` directory using JSON templates
- Use consistent naming patterns for service accounts and roles

### Resource Management

- Allocate appropriate CPU and memory resources based on cluster size
- Set resource limits to prevent resource starvation
- Consider dedicated node groups for resource-intensive addons
- Use Karpenter or node selectors to place addons on appropriate nodes
- Configure addon resource requests and limits appropriate to the environment

### Monitoring Considerations

- Monitor the health of addons with Prometheus and CloudWatch
- Set up alerts for addon failures
- Configure appropriate log levels for troubleshooting
- Create dashboards for critical addon metrics
- Enable audit logging for security-critical addons

## 6. Troubleshooting

### Common Issues and Solutions

| Issue | Possible Causes | Solutions |
|-------|----------------|-----------|
| Addon installation fails | IAM permissions, resource constraints | Check IAM roles, adjust resource requests |
| VPC CNI network issues | IP address exhaustion, subnet configuration | Check available IPs, adjust CNI configuration |
| EBS volumes not provisioning | IAM permissions, quota limits | Verify IAM roles, check EC2 quotas |
| ADOT not sending metrics | Configuration issues, IAM permissions | Check configuration, verify IAM permissions |
| Karpenter not scaling | NodePool configuration, EC2 quota limits | Review NodePool, check EC2 service quotas |

### Debugging Commands

```bash
# Check addon status
kubectl get addon -n kube-system

# Check IAM role configuration
aws iam get-role --role-name <role-name>

# View addon logs
kubectl logs -n kube-system -l app=aws-ebs-csi-driver

# Check Helm releases
helm list -A

# Describe a specific addon
kubectl describe addon aws-ebs-csi-driver -n kube-system
```