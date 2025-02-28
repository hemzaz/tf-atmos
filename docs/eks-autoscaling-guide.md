# EKS Autoscaling Guide: Karpenter and KEDA

_Last Updated: February 27, 2025_

This guide provides detailed information on implementing and configuring autoscaling for Amazon EKS clusters using Karpenter for node (infrastructure) scaling and KEDA for pod (workload) scaling.

## 1. Introduction to EKS Autoscaling

### Autoscaling Levels

Properly scaling Kubernetes workloads involves two distinct but complementary mechanisms:

1. **Pod Autoscaling**: Adjusting the number of pods running your applications based on metrics like CPU, memory usage, or custom metrics.
2. **Node Autoscaling**: Automatically adding or removing nodes from the Kubernetes cluster to accommodate pod demand.

### Solution Components

Our implementation uses two best-in-class solutions:

- **Karpenter**: A node provisioning project built for Kubernetes that automatically provisions new nodes in response to unschedulable pods.
- **KEDA** (Kubernetes Event-driven Autoscaling): A pod autoscaler that supports multiple event sources and custom metrics beyond what's available in the Horizontal Pod Autoscaler (HPA).

## 2. Karpenter: Node Autoscaling

### How Karpenter Works

Karpenter directly observes pod requirements and responds by provisioning nodes that precisely match pod requirements. This results in:

- Faster node provisioning (typically 15-60 seconds)
- More efficient resource allocation
- Better instance type selection
- Reduced costs through just-in-time provisioning

### Key Concepts

- **NodePool**: Defines the constraints and requirements for creating nodes
- **EC2NodeClass**: Defines the EC2-specific configuration for nodes
- **Provisioning**: The process of selecting and creating an appropriate node

### Karpenter vs. Cluster Autoscaler

| Feature | Karpenter | Cluster Autoscaler |
|---------|-----------|-------------------|
| Scheduling | Pod-driven | Node group-driven |
| Instance types | Diverse (can use any suitable instance) | Limited to predefined node groups |
| Provisioning time | Typically 15-60 seconds | Usually 3-10 minutes |
| Scalability | Highly scalable | Limited by node group configurations |
| Setup complexity | Simpler | More complex |
| AWS integration | Deeper integration | Generic cloud provider integration |

### Implementation in Atmos

Karpenter is implemented as a Helm chart in the EKS addons component:

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
```

### Configuration Examples

#### Basic NodePool and EC2NodeClass

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r", "t"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s

---

apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: karpenter-node-role
  securityGroupSelector:
    Name: "testenv-01-main-node-sg"
  subnetSelector:
    Name: "testenv-01-private-*"
```

#### Advanced NodePool with Spot Instances

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-pool
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["4"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot"]
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  limits:
    cpu: 500
    memory: 500Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 60s
```

#### Node Affinity and Taints

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: gpu-nodes
spec:
  template:
    spec:
      requirements:
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ["g4dn.xlarge", "g4dn.2xlarge"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
      taints:
        - key: "nvidia.com/gpu"
          value: "true"
          effect: "NoSchedule"
  limits:
    cpu: 100
    memory: 100Gi
    "nvidia.com/gpu": 10
```

## 3. KEDA: Pod Autoscaling

### How KEDA Works

KEDA extends Kubernetes' built-in Horizontal Pod Autoscaler (HPA) with support for dozens of event sources and custom metrics. It enables:

- Event-driven autoscaling based on external metrics
- Scaling to zero when there's no load
- Scaling based on AWS service metrics (SQS, DynamoDB, CloudWatch)
- Custom scaling triggers

### Key Concepts

- **ScaledObject**: Defines scaling rules for deployments, stateful sets, etc.
- **ScaledJob**: Defines scaling rules for Jobs
- **Triggers**: Event sources that prompt scaling actions
- **Scalers**: Components that interface with external metrics sources

### KEDA vs. Standard HPA

| Feature | KEDA | Standard HPA |
|---------|------|--------------|
| Metrics sources | 40+ event sources and external metrics | Limited to CPU, memory, and custom metrics with adapters |
| Scaling to zero | Supported | Not supported natively |
| AWS integration | Native support for SQS, DynamoDB, CloudWatch | Requires custom metric adapters |
| Configuration | More flexible | More limited |

### Implementation in Atmos

KEDA is implemented as a Helm chart in the EKS addons component:

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
    metricsServer.useHostNetwork: false
```

### Configuration Examples

#### AWS SQS Queue Scaler

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: sqs-queue-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: sqs-consumer
    kind: Deployment
  minReplicaCount: 1
  maxReplicaCount: 10
  pollingInterval: 15
  cooldownPeriod: 30
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-west-2.amazonaws.com/123456789012/my-sample-queue
        queueLength: "5"
        awsRegion: "eu-west-2"
        identityOwner: "operator"
```

#### CloudWatch Metrics Scaler

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cloudwatch-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: api-service
    kind: Deployment
  minReplicaCount: 1
  maxReplicaCount: 10
  pollingInterval: 30
  cooldownPeriod: 300
  triggers:
    - type: aws-cloudwatch
      metadata:
        namespace: "AWS/SQS"
        dimensionName: QueueName
        dimensionValue: api-request-queue
        metricName: ApproximateNumberOfMessagesVisible
        targetMetricValue: "10"
        minMetricValue: "0"
        metricStatistics: Average
        awsRegion: "eu-west-2"
        identityOwner: "operator"
```

#### CPU/Memory Scaler with Advanced Configuration

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cpu-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: web-service
    kind: Deployment
  minReplicaCount: 2
  maxReplicaCount: 20
  pollingInterval: 15
  advanced:
    restoreToOriginalReplicaCount: true
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
          - type: Percent
            value: 25
            periodSeconds: 60
  triggers:
    - type: cpu
      metadata:
        type: Utilization
        value: "75"
    - type: memory
      metadata:
        type: Utilization
        value: "80"
```

## 4. Integration and Best Practices

### Coordinating Pod and Node Scaling

For optimal cluster scaling, coordinate Karpenter and KEDA:

1. **Define resource requests accurately** in your pod specifications
2. **Set appropriate CPU and memory limits** to prevent overcommitment
3. **Use pod disruption budgets** to protect critical workloads during scaling events
4. **Configure appropriate scaling thresholds** to prevent scaling thrashing

### Resource Efficiency

To maximize resource efficiency:

1. **Enable Karpenter consolidation** to bin-pack nodes and reduce underutilization
2. **Use spot instances** for workloads that can tolerate interruptions
3. **Configure scaling to zero** with KEDA for infrequently used services
4. **Set appropriate minReplicaCount** to balance availability and cost
5. **Use topology spread constraints** to ensure even pod distribution

### Performance Considerations

To ensure fast and reliable scaling:

1. **Set appropriate polling intervals** in KEDA ScaledObjects
2. **Configure cooldown periods** to prevent oscillation
3. **Use diverse instance types** in Karpenter to improve scheduling success
4. **Enable acceleration timeouts** for faster scaling during spikes
5. **Set scaling behavior policies** to control scaling rates

### Example Integration

Running a queue processing system with both Karpenter and KEDA:

1. **KEDA** monitors SQS queue length and scales processor pods
2. **Karpenter** detects unschedulable pods and provisions appropriate nodes
3. **Processors** consume messages from the queue
4. As the queue empties, **KEDA** scales down processor pods
5. When nodes become empty, **Karpenter** consolidates and removes nodes

## 5. Monitoring and Troubleshooting

### Key Metrics to Monitor

Monitor these metrics to ensure proper autoscaling:

1. **Pod scaling events**: Track frequency and magnitude of pod scaling
2. **Node provisioning events**: Monitor node creation and termination
3. **Resource utilization**: Track CPU, memory, and custom metrics
4. **Scaling latency**: Measure time between scaling triggers and completion
5. **Unschedulable pods**: Track pods that can't be scheduled

### Common Issues and Solutions

| Issue | Possible Causes | Solutions |
|-------|----------------|-----------|
| Slow scaling | Insufficient EC2 capacity, AMI launch delays | Use diverse instance types, optimize AMI |
| Oscillating scaling | Too sensitive thresholds, short cooldown periods | Adjust thresholds, increase cooldown |
| Scaling to zero fails | Pod disruption budgets, drain failures | Check PDBs, increase timeout settings |
| Failed node provisioning | IAM permissions, security group restrictions | Check IAM roles, verify security groups |
| Incorrect pod scaling | Improper metric configuration | Verify KEDA trigger configuration |

### Debugging Tools

1. **Karpenter Logs**:
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller
   ```

2. **KEDA Logs**:
   ```bash
   kubectl logs -n keda -l app=keda-operator -c keda-operator
   ```

3. **Check Karpenter NodePools**:
   ```bash
   kubectl get nodepools
   kubectl describe nodepool default
   ```

4. **Check KEDA ScaledObjects**:
   ```bash
   kubectl get scaledobjects -A
   kubectl describe scaledobject <name> -n <namespace>
   ```

5. **View HPA created by KEDA**:
   ```bash
   kubectl get hpa -A
   ```

## 6. Implementation Checklist

To implement Karpenter and KEDA in your environment:

### Karpenter Setup

1. ✅ Configure IAM role for Karpenter service account
2. ✅ Deploy Karpenter controller via Helm chart
3. ✅ Create a node instance profile for Karpenter-managed nodes
4. ✅ Configure NodePool and EC2NodeClass resources
5. ✅ Test node provisioning with sample workloads

### KEDA Setup

1. ✅ Configure IAM role for KEDA service account
2. ✅ Deploy KEDA controller via Helm chart
3. ✅ Create ScaledObjects for your deployments
4. ✅ Configure appropriate scaling triggers
5. ✅ Test pod scaling with sample workloads

### Integration Testing

1. ✅ Deploy sample application with resource requests/limits
2. ✅ Create KEDA ScaledObject with appropriate triggers
3. ✅ Generate load to trigger pod scaling
4. ✅ Verify Karpenter provisions nodes correctly
5. ✅ Verify pods are scheduled onto new nodes
6. ✅ Reduce load and verify scale-down

## 7. Additional Resources

- [Karpenter Documentation](https://karpenter.sh/docs/)
- [KEDA Documentation](https://keda.sh/docs/)
- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Example Configurations](https://github.com/your-org/tf-atmos/tree/master/examples/eks-addons)