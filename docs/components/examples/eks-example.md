# EKS Cluster Examples

This directory contains examples for deploying and configuring Amazon EKS clusters using the Atmos framework.

## Basic EKS Cluster

Below is an example of how to deploy a simple EKS cluster with managed node groups:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    eks/cluster:
      vars:
        enabled: true
        region: us-west-2
        
        # EKS Cluster Configuration
        clusters:
          main:
            kubernetes_version: "1.28"
            endpoint_private_access: true
            endpoint_public_access: true
            
            # Node Groups
            node_groups:
              default:
                instance_types: ["m5.large"]
                desired_size: 2
                min_size: 1
                max_size: 5
                labels:
                  role: worker
                taints: []
                
        # General Configuration        
        subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        default_kubernetes_version: "1.28"
        default_cluster_log_retention_days: 90
        tags:
          Environment: dev
          Project: demo
```

## Advanced EKS Configuration

For more complex scenarios with multiple node groups and custom configurations:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    eks/cluster:
      vars:
        enabled: true
        region: us-west-2
        
        # EKS Cluster Configuration
        clusters:
          production:
            kubernetes_version: "1.28"
            endpoint_private_access: true
            endpoint_public_access: false
            kms_key_arn: "arn:aws:kms:us-west-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
            
            # Node Groups
            node_groups:
              system:
                instance_types: ["m5.large"]
                desired_size: 3
                min_size: 3
                max_size: 5
                labels:
                  role: system
                taints: []
                
              application:
                instance_types: ["c5.xlarge"]
                desired_size: 3
                min_size: 2
                max_size: 10
                labels:
                  role: application
                taints: []
                
              gpu:
                instance_types: ["g4dn.xlarge"]
                desired_size: 0
                min_size: 0
                max_size: 4
                labels:
                  role: gpu
                  accelerator: nvidia
                taints:
                  - key: "nvidia.com/gpu"
                    value: "true"
                    effect: "NoSchedule"
                
        # General Configuration        
        subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        default_kubernetes_version: "1.28"
        default_cluster_log_retention_days: 90
        tags:
          Environment: production
          Project: production-services
```

## Integration with EKS Addons

To deploy EKS with complementary addons:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    eks/cluster:
      vars:
        enabled: true
        region: us-west-2
        
        # EKS Cluster Configuration
        clusters:
          staging:
            kubernetes_version: "1.28"
            endpoint_private_access: true
            endpoint_public_access: true
            
            # Node Groups
            node_groups:
              default:
                instance_types: ["m5.large"]
                desired_size: 2
                min_size: 1
                max_size: 5
                
        # General Configuration        
        subnet_ids: ${dep.vpc.outputs.private_subnet_ids}
        default_kubernetes_version: "1.28"
        tags:
          Environment: staging
          Project: demo

    # EKS Addons component configuration
    eks-addons/addons:
      vars:
        enabled: true
        region: us-west-2
        
        # Reference to EKS cluster
        eks_cluster_id: ${dep.eks/cluster.outputs.eks_cluster_id}
        oidc_provider_arn: ${dep.eks/cluster.outputs.oidc_provider_arn}
        
        # Enable required addons
        enable_cluster_autoscaler: true
        enable_karpenter: true
        enable_aws_load_balancer_controller: true
        enable_external_dns: true
        enable_cert_manager: true
```

## Implementation Notes

1. Make sure to create a VPC component first, as EKS requires subnets to deploy into.
2. For production workloads, it's recommended to:
   - Disable public endpoint access or restrict it to specific CIDR blocks
   - Enable KMS encryption for secrets
   - Use at least 3 nodes spread across availability zones for high availability
   - Configure appropriate node group sizing based on workload requirements
3. Follow least privilege security principles for node IAM roles
4. Consider using Karpenter instead of Cluster Autoscaler for more efficient autoscaling