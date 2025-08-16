# Amazon EKS Guide

_Last Updated: March 10, 2025_

This comprehensive guide provides detailed information on deploying, managing, and operating Amazon EKS (Elastic Kubernetes Service) clusters with Atmos, including addons, autoscaling, service mesh integration, and best practices.

## Table of Contents

1. [Introduction and Overview](#introduction-and-overview)
   - [What is EKS](#what-is-eks)
   - [Key Features and Benefits](#key-features-and-benefits)
   - [Architecture Overview](#architecture-overview)

2. [EKS Cluster Management](#eks-cluster-management)
   - [Basic Cluster Configuration](#basic-cluster-configuration)
   - [Node Groups Configuration](#node-groups-configuration)
   - [Multiple Cluster Patterns](#multiple-cluster-patterns)
   - [Accessing and Managing Clusters](#accessing-and-managing-clusters)

3. [EKS Addons Framework](#eks-addons-framework)
   - [Addons Overview](#addons-overview)
   - [AWS Native Addons](#aws-native-addons)
   - [Helm-deployed Addons](#helm-deployed-addons)
   - [Version Management](#version-management)
   - [IAM Permissions for Addons](#iam-permissions-for-addons)

4. [Autoscaling Architecture](#autoscaling-architecture)
   - [Autoscaling Levels and Types](#autoscaling-levels-and-types)
   - [Cluster Autoscaler](#cluster-autoscaler)
   - [Karpenter](#karpenter)
   - [KEDA](#keda)
   - [Integration and Coordination](#integration-and-coordination)
   - [Performance Considerations](#performance-considerations)

5. [Service Mesh with Istio](#service-mesh-with-istio)
   - [Istio Architecture Overview](#istio-architecture-overview)
   - [Deployment Configuration](#deployment-configuration)
   - [Traffic Management](#traffic-management)
   - [Security Features](#security-features)
   - [Certificate Management](#certificate-management)
   - [Observability](#observability)

6. [Multi-Cluster Management](#multi-cluster-management)
   - [Configuration Approach](#configuration-approach)
   - [Resource Sharing](#resource-sharing)
   - [Cross-Cluster Communication](#cross-cluster-communication)

7. [Security Best Practices](#security-best-practices)
   - [IAM Roles and Policies](#iam-roles-and-policies)
   - [Network Security](#network-security)
   - [Pod Security](#pod-security)
   - [Secret Management](#secret-management)

8. [Reliability Engineering](#reliability-engineering)
   - [High Availability Configuration](#high-availability-configuration)
   - [Backup and Restore](#backup-and-restore)
   - [Graceful Termination](#graceful-termination)
   - [Disaster Recovery](#disaster-recovery)

9. [Performance Optimization](#performance-optimization)
   - [Resource Management](#resource-management)
   - [Node Sizing and Selection](#node-sizing-and-selection)
   - [Bottleneck Identification](#bottleneck-identification)

10. [Cost Optimization](#cost-optimization)
    - [Right-sizing Clusters](#right-sizing-clusters)
    - [Spot Instance Utilization](#spot-instance-utilization)
    - [Scaling Strategies](#scaling-strategies)

11. [Monitoring and Observability](#monitoring-and-observability)
    - [EKS-specific Monitoring](#eks-specific-monitoring)
    - [CloudWatch Integration](#cloudwatch-integration)
    - [Prometheus and Grafana](#prometheus-and-grafana)
    - [Logging Configuration](#logging-configuration)

12. [Troubleshooting Guide](#troubleshooting-guide)
    - [Common Issues](#common-issues)
    - [Debugging Techniques](#debugging-techniques)
    - [Common Error Resolution](#common-error-resolution)

13. [Implementation Checklists](#implementation-checklists)
    - [Cluster Setup](#cluster-setup)
    - [Addon Deployment](#addon-deployment)
    - [Autoscaling Configuration](#autoscaling-configuration)
    - [Service Mesh Implementation](#service-mesh-implementation)

## Introduction and Overview

### What is EKS

Amazon Elastic Kubernetes Service (EKS) is a managed Kubernetes service that simplifies deploying, managing, and scaling containerized applications using Kubernetes. EKS runs the Kubernetes control plane across multiple AWS availability zones, automatically detects and replaces unhealthy control plane instances, and provides on-demand upgrades and patching for them.

### Key Features and Benefits

- **Managed Control Plane**: AWS manages the Kubernetes control plane, including etcd and API servers
- **High Availability**: Control plane spans multiple Availability Zones for resilience
- **AWS Integration**: Seamless integration with AWS services (IAM, VPC, ELB, etc.)
- **Compliance**: Meets various compliance standards (SOC, PCI, ISO, HIPAA, etc.)
- **Automated Updates**: Simplified Kubernetes version updates
- **Flexible Compute**: Support for EC2, Fargate, and Spot instances
- **Managed Node Groups**: Simplified worker node management

### Architecture Overview

A typical EKS architecture with Atmos includes:

1. **EKS Control Plane**: Managed by AWS across multiple AZs
2. **Node Groups**: EC2 instances for running workloads
3. **Add-ons**: Kubernetes add-ons for functionality extension
4. **IAM for Service Accounts**: Fine-grained AWS service permissions
5. **VPC Networking**: Integrated with existing VPC networking
6. **Autoscaling**: Components for automatic scaling based on demand
7. **Monitoring**: Integrated CloudWatch and Prometheus monitoring

## EKS Cluster Management

### Basic Cluster Configuration

To create an EKS cluster in an environment stack:

```yaml
components:
  terraform:
    eks:
      vars:
        enabled: true
        name: "main-cluster"
        kubernetes_version: "1.28"
        
        # Networking
        vpc_id: "${output.vpc.vpc_id}"
        subnet_ids: "${output.vpc.private_subnet_ids}"
        
        # Access
        endpoint_private_access: true
        endpoint_public_access: true
        
        # Logging
        cluster_enabled_log_types:
          - api
          - audit
          - authenticator
          - controllerManager
          - scheduler
```

The `eks` component creates:
- EKS Cluster control plane
- IAM roles and policies
- Security groups
- OIDC provider for IAM roles for service accounts
- Logging configuration

### Node Groups Configuration

Node groups can be configured in the same component:

```yaml
managed_node_groups:
  main:
    min_size: 2
    max_size: 5
    desired_size: 2
    instance_types:
      - t3.medium
    capacity_type: ON_DEMAND
    labels:
      role: worker
    taints: []
  
  gpu:
    min_size: 0
    max_size: 3
    desired_size: 0
    instance_types:
      - g4dn.xlarge
    capacity_type: SPOT
    labels:
      accelerator: nvidia
    taints:
      - key: nvidia.com/gpu
        value: "true"
        effect: "NO_SCHEDULE"

  arm:
    min_size: 0
    max_size: 3
    desired_size: 1
    instance_types:
      - t4g.medium
      - t4g.large
    capacity_type: SPOT
    labels:
      arch: arm64
```

### Multiple Cluster Patterns

Atmos supports multiple EKS clusters in the same account using the multiple component instances pattern:

```yaml
components:
  terraform:
    eks/main:
      vars:
        enabled: true
        name: "main-cluster"
        vpc_id: "${output.vpc/main.vpc_id}"
        # other configurations...
        
    eks/data:
      vars:
        enabled: true
        name: "data-cluster"
        vpc_id: "${output.vpc/data.vpc_id}"
        # other configurations...
```

For multi-cluster scenarios, you can use the cluster object map pattern to simplify addon configuration:

```yaml
# Define cluster objects in a common file
eks_clusters:
  main:
    cluster_name: "main-cluster"
    oidc_provider_arn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXXXXXXXXXX"
    host: "https://ABCDEF1234567890.gr7.us-west-2.eks.amazonaws.com"
  data:
    cluster_name: "data-cluster"
    oidc_provider_arn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/YYYYYYYYYYYYYYYYYYYY"
    host: "https://FEDCBA0987654321.gr7.us-west-2.eks.amazonaws.com"
```

### Accessing and Managing Clusters

Use the Atmos AWS EKS workflow to generate and update kubeconfig entries:

```bash
# Generate kubeconfig for a specific cluster
atmos aws eks update-kubeconfig \
  --cluster-name main-cluster \
  --region us-west-2 \
  --alias main-dev-01

# List available contexts
kubectl config get-contexts

# Switch between clusters
kubectl config use-context main-dev-01
```

## EKS Addons Framework

### Addons Overview

EKS addons extend the functionality of Kubernetes clusters through AWS-native addons and community-provided solutions. Atmos provides a comprehensive EKS addons component that manages essential Kubernetes addons.

Addons can be categorized into:
1. **AWS-native EKS addons** - Managed by AWS and tightly integrated with EKS
2. **Helm-deployed addons** - Community-maintained or third-party addons deployed via Helm
3. **Operator pattern addons** - Kubernetes operators that extend the Kubernetes API

### AWS Native Addons

AWS native addons are managed directly by the EKS service and can be enabled through the eks-addons component:

```yaml
# AWS native addons configuration
aws_eks_addons:
  coredns:
    enabled: true
    addon_version: "v1.10.1-eksbuild.4"
    resolve_conflicts: "OVERWRITE"
    configuration_values: ""
  
  vpc-cni:
    enabled: true
    addon_version: "v1.14.0-eksbuild.3"
    resolve_conflicts: "OVERWRITE"
    configuration_values: |
      {
        "env": {
          "ENABLE_PREFIX_DELEGATION": "true",
          "WARM_ENI_TARGET": "1",
          "AWS_VPC_K8S_CNI_EXTERNALSNAT": "true"
        }
      }
  
  kube-proxy:
    enabled: true
    addon_version: "v1.28.1-eksbuild.1"
    resolve_conflicts: "OVERWRITE"
  
  aws-ebs-csi-driver:
    enabled: true
    addon_version: "v1.23.0-eksbuild.1"
    resolve_conflicts: "OVERWRITE"
```

| Addon | Purpose | Key Features | Recommended Version | 
|-------|---------|-------------|---------------------|
| **CoreDNS** | Service discovery | DNS resolution for cluster | v1.10.1-eksbuild.4 for EKS 1.28 |
| **VPC CNI** | Networking | AWS VPC integration, Pod networking | v1.14.0-eksbuild.3 |
| **Kube Proxy** | Networking | Network routing, service load balancing | Match Kubernetes version |
| **EBS CSI Driver** | Storage | Amazon EBS volume integration | v1.23.0-eksbuild.1 |
| **EFS CSI Driver** | Storage | Amazon EFS integration | v1.5.8-eksbuild.1 |
| **FSx CSI Driver** | Storage | Amazon FSx integration | v1.7.0-eksbuild.1 |

### Helm-deployed Addons

Most addons are deployed using Helm charts through the eks-addons component:

```yaml
components:
  terraform:
    eks-addons:
      vars:
        enabled: true
        cluster_name: "${output.eks.cluster_ids.main}"
        oidc_provider_arn: "${output.eks.oidc_provider_arns.main}"
        
        # AWS Load Balancer Controller
        aws_load_balancer_controller:
          enabled: true
          chart_version: "1.6.2"
        
        # External DNS
        external_dns:
          enabled: true
          chart_version: "6.26.3"
          settings:
            txtOwnerId: "${tenant}-${environment}"
            policy: sync
            sources:
              - service
              - ingress
        
        # Metrics Server
        metrics_server:
          enabled: true
          chart_version: "3.10.0"
        
        # AWS for Fluent Bit (logging)
        aws_for_fluentbit:
          enabled: true
          chart_version: "0.1.32"
          
        # Cert Manager
        cert_manager:
          enabled: true
          chart_version: "v1.13.2"
          create_namespace: true
          namespace: cert-manager
```

| Addon | Purpose | IAM Policy | Recommended Version |
|-------|---------|------------|---------------------|
| **AWS Load Balancer Controller** | Manages AWS ALBs/NLBs | AWSLoadBalancerControllerIAMPolicy | 1.6.2 |
| **External DNS** | Updates Route53 records | AmazonRoute53FullAccess | 6.26.3 |
| **Cluster Autoscaler** | Scales node groups | AutoScalingFullAccess | 9.29.0 |
| **Metrics Server** | Kubernetes metrics | None | 3.10.0 |
| **AWS for Fluent Bit** | Log shipping | CloudWatchLogsFullAccess | 0.1.32 |
| **Cert Manager** | Certificate management | Route53 access | v1.13.2 |
| **Prometheus** | Monitoring | None | 22.6.1 |
| **Grafana** | Dashboards | None | 6.57.4 |
| **Karpenter** | Node provisioning | Custom policy | 0.31.1 |
| **KEDA** | Event-driven autoscaling | Depends on scalers | 2.12.0 |
| **Istio** | Service mesh | None | 1.19.3 |
| **Velero** | Backup and restore | S3, EC2 access | 5.0.2 |

### Version Management

Addon versions should be compatible with your cluster version. General guidelines:

1. For AWS native addons, use the latest version compatible with your EKS version
2. For Helm charts, check the compatibility matrix for your Kubernetes version
3. Test addon updates in non-production environments first
4. Keep all addons within a cluster at compatible versions

### IAM Permissions for Addons

Most addons require IAM permissions to interact with AWS services. The eks-addons component automatically creates IAM roles for service accounts (IRSA) with appropriate permissions:

```yaml
# All IAM policies are attached to roles automatically
aws_load_balancer_controller:
  enabled: true
  chart_version: "1.6.2"
  # IAM policy defined in components/terraform/eks-addons/policies/aws-load-balancer-controller-policy.json

external_dns:
  enabled: true
  # IAM policy defined in components/terraform/eks-addons/policies/external-dns-policy.json
```

## Autoscaling Architecture

### Autoscaling Levels and Types

Kubernetes autoscaling operates at different levels:

1. **Pod-level Autoscaling**
   - Horizontal Pod Autoscaler (HPA) - Scales pod replicas
   - Vertical Pod Autoscaler (VPA) - Adjusts pod resources
   - KEDA - Event-driven autoscaling

2. **Node-level Autoscaling**
   - Cluster Autoscaler - Scales node groups based on pod pressure
   - Karpenter - Just-in-time node provisioning

Choosing the right autoscaling solution depends on your workload characteristics:

| Workload Type | Recommended Autoscaling |
|---------------|-------------------------|
| Web/API services | HPA + Cluster Autoscaler/Karpenter |
| Batch/Queue Processing | KEDA + Karpenter |
| ML/Analytics | VPA + Karpenter with GPU support |
| Consistent Load | Fixed Nodegroups, HPA |
| Dev/Test | Karpenter with aggressive scaling to zero |

### Cluster Autoscaler

The traditional Kubernetes Cluster Autoscaler scales node groups based on pending pods:

```yaml
cluster_autoscaler:
  enabled: true
  chart_version: "9.29.0"
  settings:
    autoDiscovery:
      clusterName: "${cluster_name}"
    awsRegion: "${region}"
    extraArgs:
      scan-interval: 30s
      scale-down-delay-after-add: 5m
      scale-down-unneeded-time: 5m
      max-node-provision-time: 15m
      skip-nodes-with-local-storage: false
      balance-similar-node-groups: true
      expander: least-waste
```

**Best Practices for Cluster Autoscaler:**
- Set appropriate scale-down timeouts to avoid rapid scaling
- Use node selectors or taints for specialized nodes
- Enable balancing between similar node groups
- Set reasonable min/max values for node groups
- Consider the "least-waste" expander for optimized scaling

### Karpenter

Karpenter is AWS's next-generation autoscaler that provisions right-sized nodes instantly:

```yaml
karpenter:
  enabled: true
  chart_version: "0.31.1"
  settings:
    controller:
      resources:
        requests:
          cpu: 1
          memory: 1Gi
  
  # EC2NodeClass configuration
  node_classes:
    default:
      amiFamily: AL2
      subnetSelectorTerms:
        - tags:
            Name: "*private*"
      securityGroupSelectorTerms:
        - tags:
            Name: "*node*"
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            deleteOnTermination: true
      instanceProfile: "${karpenter_instance_profile_name}"
      tags:
        karpenter.sh/discovery: "${cluster_name}"
  
  # NodePool configuration
  node_pools:
    default:
      name: default
      template:
        spec:
          nodeClassRef:
            name: default
          requirements:
            - key: "karpenter.sh/capacity-type"
              operator: "In"
              values: ["on-demand", "spot"]
            - key: "karpenter.k8s.aws/instance-category"
              operator: "In"
              values: ["t", "m"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: "Gt"
              values: ["2"]
            - key: "kubernetes.io/arch"
              operator: "In"
              values: ["amd64"]
          limits:
            cpu: 1000
            memory: 1000Gi
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
        expireAfter: 720h # 30 days
      weight: 10
```

**Advanced Karpenter Example with Multiple Node Pools:**

```yaml
node_pools:
  # General purpose workload pool
  general:
    name: general
    template:
      spec:
        nodeClassRef:
          name: default
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: "In"
            values: ["on-demand", "spot"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: "In"
            values: ["t", "m"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: "Gt"
            values: ["3"]
        limits:
          cpu: 500
          memory: 500Gi
    disruption:
      consolidationPolicy: WhenEmpty
      consolidateAfter: 30s
    weight: 10
    
  # ARM workload pool for cost optimization
  arm:
    name: arm
    template:
      spec:
        nodeClassRef:
          name: arm
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: "In"
            values: ["spot"]
          - key: "kubernetes.io/arch"
            operator: "In"
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: "In"
            values: ["t", "m", "c"]
        limits:
          cpu: 300
          memory: 300Gi
    disruption:
      consolidationPolicy: WhenEmpty
      consolidateAfter: 30s
    weight: 100  # Higher weight makes this pool preferred
  
  # GPU workload pool
  gpu:
    name: gpu
    template:
      spec:
        nodeClassRef:
          name: gpu
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: "In"
            values: ["on-demand"]
          - key: "node.kubernetes.io/instance-type"
            operator: "In"
            values: ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge"]
        taints:
          - key: "nvidia.com/gpu"
            effect: "NoSchedule"
            value: "true"
        limits:
          cpu: 200
          memory: 200Gi
          "nvidia.com/gpu": 10
    disruption:
      consolidationPolicy: WhenUnderutilized
      consolidateAfter: 300s  # 5 minutes
    weight: 1
```

**Comparison: Cluster Autoscaler vs. Karpenter**

| Feature | Cluster Autoscaler | Karpenter |
|---------|-------------------|-----------|
| **Scaling Speed** | Minutes (ASG-based) | Seconds (direct EC2 API) |
| **Node Selection** | Pre-defined node groups | Just-in-time instance selection |
| **Instance Types** | Fixed per node group | Dynamic, based on workload |
| **Bin Packing** | Limited | Advanced bin packing |
| **Flexibility** | Node groups must be pre-defined | Dynamic instance selection |
| **Multi-AZ Support** | Via multiple node groups | Automatic |
| **Spot Support** | Via spot node groups | Native with diversification |
| **Setup Complexity** | Simpler | More complex |
| **Consolidation** | Limited | Native node consolidation |
| **Integration** | Works with any Kubernetes cluster | AWS-specific |

### KEDA

Kubernetes Event-Driven Autoscaler for scaling deployments based on event sources:

```yaml
keda:
  enabled: true
  chart_version: "2.12.0"
  settings:
    metricsServer:
      enabled: false  # Use existing metrics server
```

**Example KEDA ScaledObject for SQS:**

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-processor
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sqs-processor
  minReplicaCount: 0
  maxReplicaCount: 20
  pollingInterval: 15  # Seconds between scaling runs
  cooldownPeriod: 300  # Seconds to wait after scaling down
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
          - type: Percent
            value: 100
            periodSeconds: 15
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.us-west-2.amazonaws.com/123456789012/my-queue
        queueLength: "5"
        awsRegion: "us-west-2"
        identityOwner: "pod"
```

**Example KEDA CloudWatch Metrics Scaler:**

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cloudwatch-scaler
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: aws-processor
  pollingInterval: 30
  minReplicaCount: 1
  maxReplicaCount: 10
  advanced:
    restoreToOriginalReplicaCount: true
    restoreToOriginalReplicaCountTimeout: 3600
  triggers:
    - type: aws-cloudwatch
      metadata:
        namespace: "AWS/SQS"
        dimensionName: QueueName
        dimensionValue: my-queue
        metricName: ApproximateNumberOfMessagesVisible
        targetMetricValue: "5"
        minMetricValue: "0"
        awsRegion: "us-west-2"
        identityOwner: "operator"
```

**Supported KEDA Scalers for AWS:**

| Scaler | Use Case | Key Metrics | IAM Permissions |
|--------|----------|------------|----------------|
| SQS | Queue processing | Queue depth | SQS read access |
| CloudWatch | Custom metrics | Any CloudWatch metric | CloudWatch read access |
| DynamoDB | Stream processing | Stream records | DynamoDB stream access |
| Kinesis | Stream processing | Stream records | Kinesis read access |
| SNS | Event processing | Subscription backlog | SNS subscription access |

### Integration and Coordination

For optimal autoscaling, coordinate between pod-level (HPA/KEDA) and node-level (Karpenter) autoscaling:

1. **Set Appropriate Thresholds**
   - Pod scaling: Trigger at 70-80% resource utilization
   - Node scaling: Allow buffer for new pods (15-20%)

2. **Timing Coordination**
   - Pod scaling should be faster than node scaling
   - Set shorter intervals for pod scaling (10-30s)
   - Set reasonable cooldowns to avoid thrashing

3. **Over-provisioning**
   - Consider small over-provisioning for burst capacity
   - Use the Kubernetes cluster-proportional-autoscaler for system add-ons

Example configuration for coordinated scaling:

```yaml
# HPA Configuration
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

### Performance Considerations

For optimal autoscaling performance:

1. **Resource Requests and Limits**
   - Set accurate resource requests for proper scheduling
   - Consider overheads when setting limits
   - Don't set CPU limits too close to requests to avoid throttling

2. **Pod Startup Times**
   - Be aware of pod startup times for effective scaling
   - Use readiness probes with appropriate settings
   - Consider pre-scaling for predictable load patterns

3. **Scale Testing**
   - Test scaling behavior under load
   - Measure pod start times for different workloads
   - Verify coordinated scaling between pod and node levels

4. **Resource Buffers**
   - Add small resource buffers to handle spikes
   - Consider the cluster-overprovisioner pattern for immediate capacity

## Service Mesh with Istio

### Istio Architecture Overview

Istio is a service mesh that provides traffic management, security, and observability features for Kubernetes workloads. The Atmos EKS addons component includes comprehensive Istio support.

Istio consists of these core components:
- **istio-base** - CRDs and base components
- **istiod** - Control plane
- **istio-ingress** - Ingress gateway

```yaml
# Basic Istio configuration
istio:
  enabled: true
  chart_version: "1.19.3"
  create_namespace: true
  namespace: istio-system
  settings:
    profile: default
    components:
      ingressGateways:
        - name: istio-ingressgateway
          enabled: true
          k8s:
            serviceAnnotations:
              service.beta.kubernetes.io/aws-load-balancer-type: nlb
              service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

### Deployment Configuration

For production Istio deployments, consider this enhanced configuration:

```yaml
istio:
  enabled: true
  chart_version: "1.19.3"
  create_namespace: true
  namespace: istio-system
  settings:
    profile: default
    meshConfig:
      accessLogFile: /dev/stdout
      enableTracing: true
      defaultConfig:
        tracing:
          sampling: 100
          zipkin:
            address: jaeger-collector.observability:9411
    components:
      ingressGateways:
        - name: istio-ingressgateway
          enabled: true
          k8s:
            resources:
              requests:
                cpu: 200m
                memory: 256Mi
              limits:
                cpu: 1000m
                memory: 1Gi
            hpaSpec:
              minReplicas: 2
              maxReplicas: 5
              metrics:
                - type: Resource
                  resource:
                    name: cpu
                    target:
                      type: Utilization
                      averageUtilization: 80
            serviceAnnotations:
              service.beta.kubernetes.io/aws-load-balancer-type: nlb
              service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
              external-dns.alpha.kubernetes.io/hostname: "*.${var.domain_name}"
            service:
              type: LoadBalancer
              ports:
                - name: http2
                  port: 80
                  targetPort: 8080
                - name: https
                  port: 443
                  targetPort: 8443
      pilot:
        enabled: true
        k8s:
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              cpu: 1000m
              memory: 4Gi
          hpaSpec:
            minReplicas: 2
            maxReplicas: 5
            metrics:
              - type: Resource
                resource:
                  name: cpu
                  target:
                    type: Utilization
                    averageUtilization: 80
```

### Traffic Management

Istio provides powerful traffic management capabilities through custom resources:

**Gateway configuration:**

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: main-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.example.com"
    tls:
      httpsRedirect: true
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*.example.com"
    tls:
      mode: SIMPLE
      credentialName: example-com-tls
```

**VirtualService for routing:**

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: app-routes
  namespace: default
spec:
  hosts:
  - "app.example.com"
  gateways:
  - istio-system/main-gateway
  http:
  - match:
    - uri:
        prefix: /api
    route:
    - destination:
        host: api-service
        port:
          number: 8080
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend-service
        port:
          number: 80
```

**Traffic splitting for canary deployments:**

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: api-canary
  namespace: default
spec:
  hosts:
  - api-service
  http:
  - route:
    - destination:
        host: api-service
        subset: v1
      weight: 90
    - destination:
        host: api-service
        subset: v2
      weight: 10
```

### Security Features

Istio provides comprehensive security features:

**Service-to-service authentication:**

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: default
spec:
  mtls:
    mode: STRICT
```

**Authorization policy:**

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-access
  namespace: default
spec:
  selector:
    matchLabels:
      app: api-service
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/frontend-service"]
    to:
    - operation:
        methods: ["GET"]
```

### Certificate Management

For TLS certificates, Istio can integrate with cert-manager and External Secrets:

**Option 1: Direct Certificate Management with cert-manager:**

```yaml
# Certificate request
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-tls
  namespace: istio-system
spec:
  secretName: example-com-tls
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  subject:
    organizations:
      - Example Organization
  dnsNames:
  - "*.example.com"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

**Option 2: External Secrets Integration (recommended):**

```yaml
# External secret for TLS certificate
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: tls-certificate
  namespace: istio-system
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: secretsmanager
    kind: ClusterSecretStore
  target:
    name: example-com-tls
    template:
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ .tls.certificate }}"
        tls.key: "{{ .tls.privateKey }}"
  data:
  - secretKey: tls
    remoteRef:
      key: "certificates/example/com/wildcard"
```

### Observability

Istio integrates with various observability tools:

**Kiali for visualization:**

```yaml
kiali:
  enabled: true
  chart_version: "1.75.0"
  create_namespace: true
  namespace: istio-system
  settings:
    auth:
      strategy: anonymous
    deployment:
      ingress:
        enabled: true
        annotations:
          kubernetes.io/ingress.class: alb
        hosts:
          - kiali.example.com
```

**Jaeger for tracing:**

```yaml
jaeger:
  enabled: true
  chart_version: "0.71.12"
  create_namespace: true
  namespace: observability
  settings:
    provisionDataStore:
      cassandra: false
      elasticsearch: true
    storage:
      type: elasticsearch
      elasticsearch:
        host: elasticsearch-master.observability
        usePassword: false
```

## Multi-Cluster Management

### Configuration Approach

For multi-cluster management, use the cluster object map pattern:

```yaml
# Define common cluster variables for multi-cluster management
eks_clusters:
  main:
    cluster_name: "main-cluster" 
    oidc_provider_arn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/XXXXXXXXXXXXXXXXXXXX"
    host: "https://ABCDEF1234567890.gr7.us-west-2.eks.amazonaws.com"
  data:
    cluster_name: "data-cluster"
    oidc_provider_arn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/YYYYYYYYYYYYYYYYYYYY"
    host: "https://FEDCBA0987654321.gr7.us-west-2.eks.amazonaws.com"

# Use map for addon configuration
components:
  terraform:
    eks-addons/main:
      vars:
        enabled: true
        cluster_name: "${eks_clusters.main.cluster_name}"
        oidc_provider_arn: "${eks_clusters.main.oidc_provider_arn}"
    
    eks-addons/data:
      vars:
        enabled: true
        cluster_name: "${eks_clusters.data.cluster_name}"
        oidc_provider_arn: "${eks_clusters.data.oidc_provider_arn}"
```

### Resource Sharing

For sharing resources between clusters:

1. **Cross-cluster service discovery** - Use AWS Cloud Map or external DNS
2. **Cross-cluster authorization** - Configure IAM roles with cross-account access
3. **Shared storage** - Use centralized S3, RDS, or EFS resources

### Cross-Cluster Communication

Enable cross-cluster communication:

```yaml
# Configure AWS Cloud Map for service discovery
components:
  terraform:
    service-discovery:
      vars:
        enabled: true
        namespace_name: "services.example.com"
        vpc_id: "${output.vpc.vpc_id}"
        clusters:
          - name: "main"
            endpoint: "${eks_clusters.main.host}"
          - name: "data"
            endpoint: "${eks_clusters.data.host}"
```

## Security Best Practices

### IAM Roles and Policies

Use IAM Roles for Service Accounts (IRSA) with the principle of least privilege:

```yaml
# Service account with IAM role
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/app-service-role
```

For cluster-level roles:

```yaml
components:
  terraform:
    eks:
      vars:
        # Map IAM roles to Kubernetes RBAC groups
        map_roles:
          - rolearn: "arn:aws:iam::123456789012:role/developers"
            username: "developers:{{SessionName}}"
            groups:
              - "system:developers"
          - rolearn: "arn:aws:iam::123456789012:role/operators"
            username: "operators:{{SessionName}}"
            groups:
              - "system:operators"
```

### Network Security

Implement network security controls:

```yaml
# Network policies to restrict traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-traffic
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Pod Security

Apply pod security standards:

```yaml
# Pod Security Admission configuration
components:
  terraform:
    eks:
      vars:
        # Enable Pod Security Standards
        cluster_security_group_additional_rules:
          ingress_self_all:
            description: Node to node all ports/protocols
            protocol: "-1"
            from_port: 0
            to_port: 0
            type: "ingress"
            self: true

# Create Pod Security Standards
apiVersion: kubectl.kubernetes.io/v1alpha1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - configMap
    - emptyDir
    - projected
    - secret
    - downwardAPI
    - persistentVolumeClaim
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: MustRunAsNonRoot
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: MustRunAs
    ranges:
      - min: 1
        max: 65535
  fsGroup:
    rule: MustRunAs
    ranges:
      - min: 1
        max: 65535
  readOnlyRootFilesystem: true
```

### Secret Management

Manage secrets securely with External Secrets Operator:

```yaml
# External secrets configuration
components:
  terraform:
    external-secrets:
      vars:
        enabled: true
        create_namespace: true
        cluster_name: "${eks_clusters.main.cluster_name}"
        oidc_provider_arn: "${eks_clusters.main.oidc_provider_arn}"
```

Set up secret stores:

```yaml
# Configure Secret Store 
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

## Reliability Engineering

### High Availability Configuration

Ensure high availability with proper configuration:

```yaml
components:
  terraform:
    eks:
      vars:
        # HA Control Plane (AWS managed)
        endpoint_private_access: true
        endpoint_public_access: true
        
        # Worker nodes across multiple AZs
        subnet_ids: "${output.vpc.private_subnet_ids}" # Across AZs
        
        # Multiple node groups
        managed_node_groups:
          group1:
            min_size: 1
            max_size: 3
            desired_size: 2
            instance_types:
              - m5.large
            subnet_ids: "${slice(output.vpc.private_subnet_ids, 0, 1)}"
          
          group2:
            min_size: 1
            max_size: 3
            desired_size: 2
            instance_types:
              - m5.large
            subnet_ids: "${slice(output.vpc.private_subnet_ids, 1, 2)}"
          
          group3:
            min_size: 1
            max_size: 3
            desired_size: 2
            instance_types:
              - m5.large
            subnet_ids: "${slice(output.vpc.private_subnet_ids, 2, 3)}"
```

### Backup and Restore

Implement backup and restore with Velero:

```yaml
# Velero configuration
velero:
  enabled: true
  chart_version: "5.0.2"
  create_namespace: true
  namespace: velero
  settings:
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.7.1
        volumeMounts:
          - mountPath: /target
            name: plugins
    configuration:
      provider: aws
      backupStorageLocation:
        provider: aws
        bucket: my-eks-backups
        config:
          region: us-west-2
      volumeSnapshotLocation:
        provider: aws
        config:
          region: us-west-2
    credentials:
      useSecret: false
      secretContents:
        cloud: ""
```

Schedule regular backups:

```yaml
# Backup schedule
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 0 * * *"
  template:
    includedNamespaces:
      - default
      - app
    includedResources:
      - deployments
      - services
      - persistentvolumeclaims
      - persistentvolumes
    labelSelector:
      matchExpressions:
        - key: backup
          operator: In
          values:
            - "true"
    storageLocation: default
    ttl: 720h # 30 days
```

### Graceful Termination

Configure graceful termination with Pod Disruption Budgets:

```yaml
# Pod Disruption Budget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
  namespace: default
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      app: application
```

Install Node Termination Handler for Spot instances:

```yaml
# AWS Node Termination Handler
aws_node_termination_handler:
  enabled: true
  chart_version: "0.21.0"
  settings:
    enableSpotInterruptionDraining: true
    enableRebalanceMonitoring: true
    enableScheduledEventDraining: true
    nodeTerminationGracePeriod: 120
    podTerminationGracePeriod: 60
```

### Disaster Recovery

Document and test disaster recovery procedures:

1. **Regular Backups** - Automate with Velero
2. **Multi-Region Strategy** - Consider backup clusters in alternate regions
3. **Recovery Testing** - Test restoration procedures monthly
4. **Runbooks** - Create detailed recovery runbooks
5. **Critical Path Analysis** - Identify and document dependencies

## Performance Optimization

### Resource Management

Optimize resource allocation:

```yaml
# Example of right-sized resources
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web-app
        image: web-app:latest
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
```

Use horizontal scaling when possible:

```yaml
# HPA for performance
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Node Sizing and Selection

Choose appropriate instance types based on workload:

| Workload Type | Recommended Instance Types |
|---------------|----------------------------|
| General purpose | t3.medium, m5.large, m6i.large |
| Memory intensive | r5.large, r6i.xlarge, x2gd.large |
| Compute intensive | c5.large, c6i.large, c6g.large |
| GPU workloads | g4dn.xlarge, g5.xlarge, p3.2xlarge |
| Cost-optimized | t4g.medium, m6g.large, c6g.large |

Configure mixed instance policies for node groups:

```yaml
# Mixed instance policy
components:
  terraform:
    eks:
      vars:
        managed_node_groups:
          compute:
            min_size: 1
            max_size: 10
            desired_size: 2
            instance_types:
              - c5.large
              - c5a.large
              - c6i.large
              - c6a.large
            capacity_type: SPOT
```

### Bottleneck Identification

Use metrics and monitoring to identify bottlenecks:

1. **Horizontal Pod Autoscaler** - Monitor scaling events and CPU/memory metrics
2. **Karpenter** - Review provisioning decisions
3. **Kubernetes Dashboard** - View resource usage across the cluster
4. **CloudWatch Container Insights** - Track detailed container metrics

## Cost Optimization

### Right-sizing Clusters

Optimize cluster resources for cost:

```yaml
# Optimized node groups
components:
  terraform:
    eks:
      vars:
        managed_node_groups:
          # On-demand for critical workloads
          critical:
            min_size: 2
            max_size: 5
            desired_size: 2
            instance_types:
              - m5.large
            capacity_type: ON_DEMAND
            
          # Spot for general workloads
          general:
            min_size: 1
            max_size: 20
            desired_size: 3
            instance_types:
              - m5.large
              - m5a.large
              - m5n.large
              - m6i.large
            capacity_type: SPOT
            
          # ARM-based for cost-efficiency
          arm:
            min_size: 0
            max_size: 10
            desired_size: 1
            instance_types:
              - m6g.large
              - t4g.medium
            capacity_type: SPOT
```

### Spot Instance Utilization

Maximize Spot instance usage with Karpenter:

```yaml
# Karpenter with Spot preference
karpenter:
  enabled: true
  node_pools:
    spot:
      name: spot
      template:
        spec:
          nodeClassRef:
            name: default
          requirements:
            - key: "karpenter.sh/capacity-type"
              operator: "In"
              values: ["spot"]
            - key: "kubernetes.io/arch"
              operator: "In"
              values: ["amd64", "arm64"]
            - key: "node.kubernetes.io/instance-type"
              operator: "In"
              values:
                - "m6i.large"
                - "m6a.large"
                - "m5.large"
                - "m5a.large"
                - "m6g.large"
                - "m7g.large"
                - "t3.medium"
                - "t3a.medium"
                - "t4g.medium"
      weight: 100  # Prefer Spot instances
```

Add node selectors for workloads that can tolerate interruptions:

```yaml
# Workloads that can use Spot
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-processor
spec:
  replicas: 3
  selector:
    matchLabels:
      app: batch-processor
  template:
    metadata:
      labels:
        app: batch-processor
    spec:
      nodeSelector:
        karpenter.sh/capacity-type: spot
      tolerations:
      - key: "node.kubernetes.io/spot"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: processor
        image: processor:latest
```

### Scaling Strategies

Implement cost-efficient scaling strategies:

1. **Environment Scheduling** - Scale non-production environments down after hours
2. **Batch Workload Planning** - Schedule batch jobs during low-demand periods
3. **Cluster Packing** - Use Karpenter consolidation to optimize node usage

Karpenter disruption configuration for consolidation:

```yaml
# Enable consolidation
karpenter:
  enabled: true
  node_pools:
    default:
      disruption:
        consolidationPolicy: WhenUnderutilized
        consolidateAfter: 30s
```

## Monitoring and Observability

### EKS-specific Monitoring

Enable Container Insights and Prometheus:

```yaml
# CloudWatch Container Insights
aws_cloudwatch_metrics:
  enabled: true
  chart_version: "0.0.8"
  settings:
    clusterName: "${cluster_name}"
    
# Prometheus
prometheus:
  enabled: true
  chart_version: "22.6.1"
  create_namespace: true
  namespace: observability
  settings:
    server:
      persistentVolume:
        enabled: true
        size: 50Gi
    alertmanager:
      enabled: true
      persistentVolume:
        enabled: true
        size: 10Gi
    nodeExporter:
      enabled: true
    pushgateway:
      enabled: true
```

### CloudWatch Integration

Send Kubernetes metrics to CloudWatch:

```yaml
# Fluent Bit for CloudWatch Logs
aws_for_fluentbit:
  enabled: true
  chart_version: "0.1.32"
  settings:
    cloudWatch:
      enabled: true
      region: "${region}"
      logGroupName: "/aws/eks/${cluster_name}/logs"
      logGroupTemplate: "/aws/eks/${cluster_name}/pods/{namespace_name}/{pod_name}"
      logStreamTemplate: "{date_time}"
```

### Prometheus and Grafana

Deploy Prometheus and Grafana for detailed monitoring:

```yaml
# Grafana
grafana:
  enabled: true
  chart_version: "6.57.4"
  create_namespace: true
  namespace: observability
  settings:
    persistence:
      enabled: true
      size: 10Gi
    admin:
      existingSecret: grafana-admin
      userKey: admin-user
      passwordKey: admin-password
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-server.observability:9090
          isDefault: true
        - name: CloudWatch
          type: cloudwatch
          jsonData:
            authType: default
            defaultRegion: "${region}"
    dashboardProviders:
      dashboardproviders.yaml:
        apiVersion: 1
        providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
```

### Logging Configuration

Configure cluster-wide logging:

```yaml
# Fluent Bit configuration
aws_for_fluentbit:
  enabled: true
  chart_version: "0.1.32"
  create_namespace: true
  namespace: logging
  settings:
    firehose:
      enabled: false
    kinesis:
      enabled: false
    elasticsearch:
      enabled: false
    cloudWatch:
      enabled: true
      region: "${region}"
      logGroupName: "/aws/eks/${cluster_name}/logs"
      logGroupTemplate: "/aws/eks/${cluster_name}/pods/{namespace_name}/{pod_name}"
      logStreamTemplate: "{date_time}"
    filters:
      - name: kubernetes
        match: "kube.*"
        type: kubernetes
        body: |
          Buffer_Size 512KB
          K8S-Logging.Exclude On
          K8S-Logging.Exclude-Object  {"match":"^\/var\/log\/containers\/.*", "Regex":"true"}
```

## Troubleshooting Guide

### Common Issues

1. **Cluster Creation Failures**
   - Check IAM permissions
   - Verify VPC and subnet configuration
   - Check security group settings
   - Review CloudTrail for API errors

2. **Node Group Issues**
   - Verify IAM role permissions
   - Check launch template configuration
   - Verify capacity type availability
   - Review auto scaling group status

3. **Addon Installation Problems**
   - Check OIDC provider configuration
   - Verify IAM role for service accounts
   - Check Helm chart version compatibility
   - Review pod logs for errors

4. **Autoscaling Issues**
   - Verify metric sources
   - Check scale-up/scale-down thresholds
   - Review autoscaler logs
   - Check for disruption budgets blocking scale-down

5. **Network Connectivity Issues**
   - Verify security groups allow traffic
   - Check route tables and subnets
   - Verify AWS CNI configuration
   - Test service-to-service connectivity

6. **Permission Problems**
   - Verify IAM roles and policies
   - Check Kubernetes RBAC configuration
   - Review service account annotations
   - Test permissions using the AWS CLI

### Debugging Techniques

Use these commands for troubleshooting:

```bash
# Get EKS cluster information
aws eks describe-cluster --name cluster-name

# Check node status
kubectl get nodes -o wide

# View pod status across all namespaces
kubectl get pods -A -o wide

# Check specific pod logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Describe pod for events and status
kubectl describe pod <pod-name> -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>

# View cluster events
kubectl get events --sort-by='.lastTimestamp' -A

# Check addon status
kubectl get deployments -n kube-system

# View IRSA configuration
kubectl describe serviceaccount <sa-name> -n <namespace>

# Test IAM permissions from pod
kubectl exec -it <pod-name> -n <namespace> -- aws sts get-caller-identity

# Check CNI configuration
kubectl describe daemonset aws-node -n kube-system
```

For Istio issues:

```bash
# Check Istio proxy status
istioctl proxy-status

# Analyze Istio config
istioctl analyze

# Check gateway status
kubectl get gateway -A

# View VirtualService configuration
kubectl get virtualservice -A -o yaml

# Debug Istio traffic
istioctl dashboard envoy <pod-name>.<namespace>
```

For Karpenter issues:

```bash
# View Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller

# Check node pools
kubectl get nodepool -o yaml

# Check node classes
kubectl get ec2nodeclass -o yaml

# View pending pods
kubectl get pods -A --field-selector=status.phase=Pending
```

### Common Error Resolution

1. **NodeCreationFailure - EC2 API errors**
   - Check IAM role permissions
   - Verify instance type availability in the region/AZ
   - Check service quotas in AWS account

2. **ImagePullBackOff - Container image issues**
   - Verify image name and tag
   - Check repository access
   - Set up image pull secrets if needed

3. **CrashLoopBackOff - Application crashes**
   - Check container logs
   - Verify environment variables
   - Check resource constraints

4. **IRSA Authentication failures**
   - Verify OIDC provider is properly configured
   - Check service account annotations
   - Validate IAM role trust relationship
   - Confirm AWS region configuration

5. **"Status: Degraded" for AWS addons**
   - Check addon version compatibility with Kubernetes version
   - Look for pending pods or failed deployments
   - Review CloudTrail for API errors
   - Check IAM permissions for service accounts

## Implementation Checklists

### Cluster Setup

✅ Pre-deployment check:
- [ ] VPC and subnets correctly configured
- [ ] IAM roles and policies ready
- [ ] Security groups properly set up
- [ ] CIDR range planning complete

✅ Cluster deployment:
- [ ] Choose appropriate Kubernetes version
- [ ] Configure private/public endpoint access
- [ ] Enable necessary log types
- [ ] Set up node groups with appropriate instance types
- [ ] Configure IRSA with OIDC provider

✅ Post-deployment verification:
- [ ] Verify cluster control plane status
- [ ] Check node group scaling and status
- [ ] Test kubeconfig and API access
- [ ] Verify security group connectivity
- [ ] Check pod networking functionality

### Addon Deployment

✅ Core addons:
- [ ] AWS VPC CNI
- [ ] CoreDNS
- [ ] kube-proxy
- [ ] AWS EBS CSI Driver

✅ Essential addons:
- [ ] AWS Load Balancer Controller
- [ ] Metrics Server
- [ ] External DNS (if using Route53)
- [ ] Cluster Autoscaler or Karpenter

✅ Monitoring addons:
- [ ] CloudWatch Container Insights
- [ ] Prometheus and Grafana
- [ ] AWS for Fluent Bit

✅ Security addons:
- [ ] Cert Manager
- [ ] External Secrets
- [ ] AWS Node Termination Handler

### Autoscaling Configuration

✅ Pod-level autoscaling:
- [ ] HPA configuration for deployments
- [ ] KEDA setup for event-driven workloads
- [ ] Resource requests/limits properly set

✅ Node-level autoscaling:
- [ ] Choose between Cluster Autoscaler and Karpenter
- [ ] Configure node groups with min/max sizes
- [ ] Set up Karpenter node pools and node classes
- [ ] Configure consolidation policies

✅ Performance testing:
- [ ] Test scaling under load
- [ ] Verify scale-down behavior
- [ ] Check resource allocation efficiency
- [ ] Monitor scaling events and triggers

### Service Mesh Implementation

✅ Istio installation:
- [ ] Install istio-base, istiod, and ingress gateway
- [ ] Configure proper resource requests/limits
- [ ] Set up gateway with appropriate service type
- [ ] Enable access logging and tracing

✅ Traffic management:
- [ ] Configure Gateway resources
- [ ] Set up VirtualServices for routing
- [ ] Implement DestinationRules for subsets
- [ ] Test traffic splitting for canary deployments

✅ Security configuration:
- [ ] Set up mTLS authentication
- [ ] Configure AuthorizationPolicies
- [ ] Integrate with cert-manager or External Secrets
- [ ] Test end-to-end encryption

✅ Observability:
- [ ] Deploy Kiali for visualization
- [ ] Set up Jaeger for tracing
- [ ] Configure Prometheus for metrics
- [ ] Create Grafana dashboards for Istio