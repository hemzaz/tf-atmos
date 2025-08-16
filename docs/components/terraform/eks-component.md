# EKS (Elastic Kubernetes Service) Component

_Last Updated: February 28, 2025_

A comprehensive AWS EKS infrastructure component that creates and manages production-ready Kubernetes clusters with multiple node groups, advanced security features, and extensive validation.

## Overview

This component creates and manages EKS clusters with the following features:

- Multi-cluster support with different configurations
- Managed node groups with flexible scaling options
- KMS encryption for cluster secrets
- IAM roles for service accounts (IRSA) with OIDC provider
- CloudWatch logging with configurable retention periods
- Strong validation and safety measures to prevent misconfigurations
- High availability with multi-AZ deployment
- Integration with other AWS services through IAM roles

## Architecture

The EKS component creates a comprehensive Kubernetes infrastructure on AWS:

```
                           +--------------------+
                           |                    |
                           |  AWS EKS Control   |
                           |     Plane          |
                           |                    |
                           +---------+----------+
                                     |
                                     | (Control plane to data plane)
                                     |
    +-------------------------------+--------------------------------+
    |                               |                                |
+---v---+                       +---v---+                        +---v---+
|       |                       |       |                        |       |
| Node  |                       | Node  |                        | Node  |
| Group |                       | Group |                        | Group |
| (AZ1) |                       | (AZ2) |                        | (AZ3) |
|       |                       |       |                        |       |
+---+---+                       +---+---+                        +---+---+
    |                               |                                |
    +-------------------------------+--------------------------------+
                                    |
                      +-------------v--------------+
                      |                            |
                      |      Cluster Security      |
                      |         Group              |
                      |                            |
                      +-------------+--------------+
                                    |
                                    |
    +---------------+---------------+----------------+----------------+
    |               |               |                |                |
+---v---+       +---v---+       +---v---+        +---v---+        +---v---+
|       |       |       |       |       |        |       |        |       |
| KMS   |       | IAM   |       | Cloud |        | OIDC  |        | VPC   |
| Key   |       | Roles |       | Watch |        | Prov- |        | Config|
|       |       |       |       | Logs  |        | ider  |        |       |
+-------+       +-------+       +-------+        +-------+        +-------+
```

## Usage

### Basic Usage

```yaml
# catalog/eks.yaml
components:
  terraform:
    eks:
      vars:
        region: ${region}
        subnet_ids: ${output.vpc.private_subnet_ids}
        
        clusters:
          primary:
            kubernetes_version: "1.28"
            endpoint_private_access: true
            endpoint_public_access: false
            enabled_cluster_log_types: ["api", "audit", "authenticator"]
            
            # Node groups
            node_groups:
              system:
                instance_types: ["m5.large"]
                desired_size: 3
                min_size: 3
                max_size: 5
                disk_size: 50
        
        tags:
          Environment: ${environment}
          Owner: "Platform Team"
```

### Environment-specific Configuration

```yaml
# account/dev/us-east-1/eks.yaml
import:
  - catalog/eks

vars:
  environment: us-east-1
  region: us-east-1
  tenant: mycompany
  
  # Override catalog settings
  clusters:
    primary:
      kubernetes_version: "1.28"
      endpoint_public_access: true # Enable public access for dev environment
      
      # Override node group configuration
      node_groups:
        system:
          instance_types: ["t3.large"] # Use smaller instances for dev
          desired_size: 2
          min_size: 2
          max_size: 4
        
        # Add application node group
        application:
          instance_types: ["c5.large"]
          desired_size: 2
          min_size: 1
          max_size: 6
          labels:
            workload-type: "application"

tags:
  Environment: "Development"
  Team: "Platform"
  CostCenter: "Platform-1234"
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `region` | AWS region | `string` | - | Yes |
| `clusters` | Map of EKS cluster configurations | `map(object)` | `{}` | Yes |
| `subnet_ids` | List of subnet IDs for EKS clusters | `list(string)` | - | Yes |
| `default_kubernetes_version` | Default Kubernetes version | `string` | `"1.28"` | No |
| `default_cluster_log_retention_days` | Number of days to retain logs | `number` | `90` | No |
| `tags` | Common tags to apply to resources | `map(string)` | `{}` | Yes |

### clusters Object Structure

```yaml
clusters:
  cluster_name:
    enabled: bool                       # Optional: Whether to create this cluster, defaults to true
    kubernetes_version: string          # Optional: Kubernetes version, defaults to default_kubernetes_version
    endpoint_private_access: bool       # Optional: Whether to enable private API endpoint, defaults to true
    endpoint_public_access: bool        # Optional: Whether to enable public API endpoint, defaults to false
    subnet_ids: list(string)            # Optional: Override default subnet_ids
    security_group_ids: list(string)    # Optional: Additional security groups to attach
    kms_key_arn: string                 # Optional: KMS key ARN for encryption
    enabled_cluster_log_types: list(string) # Optional: Log types to enable, defaults to all types
    node_groups: map(object)            # Optional: Node groups configuration
    tags: map(string)                   # Optional: Additional tags for this cluster
```

### node_groups Object Structure

```yaml
node_groups:
  node_group_name:
    instance_types: list(string)        # Optional: EC2 instance types, defaults to ["t3.medium"]
    ami_type: string                    # Optional: AMI type, defaults to AL2_x86_64
    capacity_type: string               # Optional: ON_DEMAND or SPOT, defaults to ON_DEMAND
    disk_size: number                   # Optional: Disk size in GB, defaults to 50
    desired_size: number                # Optional: Desired node count, defaults to 2
    min_size: number                    # Optional: Minimum node count, defaults to 1
    max_size: number                    # Optional: Maximum node count, defaults to 4
    taints: list(object)                # Optional: Kubernetes taints for nodes
    labels: map(string)                 # Optional: Kubernetes labels for nodes
    tags: map(string)                   # Optional: Additional tags for this node group
```

## Outputs

| Name | Description |
|------|-------------|
| `cluster_ids` | Map of cluster names to cluster IDs |
| `cluster_arns` | Map of cluster names to cluster ARNs |
| `cluster_endpoints` | Map of cluster names to cluster endpoints |
| `cluster_ca_data` | Map of cluster names to cluster CA certificate data |
| `node_group_arns` | Map of node group names to node group ARNs |
| `oidc_provider_arns` | Map of cluster names to OIDC provider ARNs |
| `cluster_security_group_ids` | Map of cluster names to cluster security group IDs |
| `node_role_arns` | Map of cluster names to node IAM role ARNs |

## Features

### Multi-Cluster Management

Create multiple EKS clusters in a single component:

```yaml
clusters:
  prod:
    kubernetes_version: "1.28"
    endpoint_private_access: true
    endpoint_public_access: false
  
  staging:
    kubernetes_version: "1.27"
    endpoint_private_access: true
    endpoint_public_access: true
```

### Advanced Node Group Configuration

Configure specialized node groups for different workloads:

```yaml
clusters:
  primary:
    node_groups:
      # System nodes for cluster-critical components
      system:
        instance_types: ["m5.large"]
        desired_size: 3
        min_size: 3
        max_size: 5
        taints:
          - key: "dedicated"
            value: "system"
            effect: "NoSchedule"
        labels:
          role: "system"
      
      # Application nodes for general workloads
      application:
        instance_types: ["c5.xlarge"]
        desired_size: 3
        min_size: 1
        max_size: 10
        labels:
          role: "application"
      
      # Spot instances for cost optimization
      spot:
        instance_types: ["c5.large", "c5a.large", "m5.large"]
        capacity_type: "SPOT"
        desired_size: 2
        min_size: 0
        max_size: 10
        labels:
          lifecycle: "spot"
```

### IAM Roles for Service Accounts

The component automatically creates an OIDC provider for each cluster, enabling IAM roles for service accounts (IRSA). This allows Kubernetes service accounts to assume IAM roles for secure AWS API access:

```yaml
# Example usage with outputs from this component
output "oidc_provider_arns.primary"  # Use this in eks-addons component
```

### CloudWatch Logging

Configure CloudWatch logging for EKS clusters:

```yaml
clusters:
  primary:
    enabled_cluster_log_types: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

## Examples

### Production Cluster

```yaml
vars:
  clusters:
    production:
      kubernetes_version: "1.28"
      endpoint_private_access: true
      endpoint_public_access: false
      
      node_groups:
        system:
          instance_types: ["m5.large"]
          desired_size: 3
          min_size: 3
          max_size: 5
          labels:
            role: "system"
        
        application:
          instance_types: ["c5.2xlarge"]
          desired_size: 5
          min_size: 3
          max_size: 20
          labels:
            role: "application"
```

### Cost-Optimized Development Cluster

```yaml
vars:
  clusters:
    development:
      kubernetes_version: "1.28"
      endpoint_private_access: true
      endpoint_public_access: true
      
      node_groups:
        system:
          instance_types: ["t3.medium"]
          desired_size: 2
          min_size: 1
          max_size: 3
        
        spot:
          instance_types: ["t3.large", "t3a.large", "m5.large"]
          capacity_type: "SPOT"
          desired_size: 2
          min_size: 0
          max_size: 10
```

### Multi-Tenant Cluster

```yaml
vars:
  clusters:
    multi_tenant:
      kubernetes_version: "1.28"
      
      node_groups:
        system:
          instance_types: ["m5.large"]
          desired_size: 3
          min_size: 3
          max_size: 5
          taints:
            - key: "dedicated"
              value: "system"
              effect: "NoSchedule"
        
        tenant_a:
          instance_types: ["c5.large"]
          desired_size: 3
          min_size: 1
          max_size: 10
          taints:
            - key: "tenant"
              value: "a"
              effect: "NoSchedule"
          labels:
            tenant: "a"
        
        tenant_b:
          instance_types: ["c5.large"]
          desired_size: 3
          min_size: 1
          max_size: 10
          taints:
            - key: "tenant"
              value: "b"
              effect: "NoSchedule"
          labels:
            tenant: "b"
```

## Related Components

- [**vpc**](../vpc/README.md) - For creating the VPC and subnets required by EKS
- [**eks-addons**](../eks-addons/README.md) - For installing Kubernetes add-ons and applications
- [**iam**](../iam/README.md) - For additional IAM roles needed for EKS operations
- [**secretsmanager**](../secretsmanager/README.md) - For managing Kubernetes secrets
- [**acm**](../acm/README.md) - For TLS certificates used with Kubernetes ingress

## Best Practices

- Always deploy EKS clusters across multiple Availability Zones for high availability
- Enable cluster logging for security and troubleshooting purposes
- Use KMS encryption for Kubernetes secrets
- Always use private endpoints in production environments
- Implement node group autoscaling with appropriate min/max values
- Use node selectors and taints to control workload placement
- Keep Kubernetes version current (no more than 2 versions behind latest)
- Consider using Spot instances for non-critical workloads to reduce costs
- Implement proper IAM roles and RBAC for access control

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**
   - Check IAM permissions for the service account creating the cluster
   - Ensure subnets span at least two Availability Zones

   ```bash
   # Check subnet AZ distribution
   aws ec2 describe-subnets --subnet-ids subnet-123 subnet-456 --query 'Subnets[*].AvailabilityZone'
   ```

2. **Node Group Scaling Issues**
   - Verify EC2 service quotas in the account
   - Check for proper IAM role permissions

   ```bash
   # Check autoscaling activity
   aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>
   ```

3. **API Endpoint Connectivity Problems**
   - Check security group rules
   - Verify VPC DNS settings

   ```bash
   # Test API server connectivity
   curl -k <cluster-endpoint>
   ```

4. **Kubernetes Version Upgrade Failures**
   - First update control plane, then node groups
   - Check for deprecated API usage in workloads
   - Ensure add-ons are compatible with the new version

5. **IAM Authentication Issues**
   - Check aws-auth ConfigMap configuration
   - Verify OIDC provider is correctly configured

### Validation Commands

```bash
# Validate component configuration
atmos terraform validate eks -s mycompany-dev-us-east-1

# Check component outputs after deployment
atmos terraform output eks -s mycompany-dev-us-east-1

# Get cluster information
aws eks describe-cluster --name <cluster-name> --region <region>

# Check node group status
aws eks describe-nodegroup --cluster-name <cluster-name> --nodegroup-name <nodegroup-name> --region <region>
```