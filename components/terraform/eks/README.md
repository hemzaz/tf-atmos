# EKS (Elastic Kubernetes Service) Component

This component creates and manages EKS clusters with comprehensive validation, security best practices, and detailed logging.

## Features

- Creates and manages EKS clusters with configurable settings
- Supports multiple clusters with different configurations
- Implements strong validation to prevent common errors
- Includes KMS encryption for cluster secrets
- Configures CloudWatch logging with customizable retention
- Sets up proper IAM roles and policies for cluster operation
- Implements prevent_destroy to protect against accidental deletion
- Enforces high availability with subnet validation

## Usage

```hcl
component "eks" {
  instance = "main"
  
  vars = {
    region     = "us-west-2"
    subnet_ids = ["subnet-12345678", "subnet-23456789", "subnet-34567890"]
    
    clusters = {
      "primary" = {
        kubernetes_version      = "1.28"
        endpoint_private_access = true
        endpoint_public_access  = false
        enabled_cluster_log_types = ["api", "audit", "authenticator"]
        node_groups = {
          "system" = {
            instance_types = ["m5.large"]
            desired_size  = 3
            min_size      = 3
            max_size      = 5
            disk_size     = 50
          }
        }
      }
    }
    
    tags = {
      Environment = "dev"
      Owner       = "platform-team"
    }
  }
}
```

## Validation and Safety Features

This component includes extensive validation to prevent misconfigurations:

1. **Kubernetes Version Validation**: Ensures valid Kubernetes versions in the correct format
2. **Subnet Validation**: Requires at least 2 subnets for high availability
3. **Prevent Destroy**: Protects clusters from accidental deletion
4. **Log Group Configuration**: Ensures proper logging is enabled
5. **Resource Tagging**: Enforces consistent tagging across all resources
6. **Timeouts**: Extends default timeouts to account for EKS operations

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| aws | >= 4.0.0 |
| kubernetes | >= 2.10.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| clusters | Map of EKS cluster configurations | `map(object)` | `{}` | no |
| subnet_ids | List of subnet IDs for EKS clusters | `list(string)` | n/a | yes |
| default_kubernetes_version | Default Kubernetes version | `string` | `"1.28"` | no |
| default_cluster_log_retention_days | Number of days to retain logs | `number` | `90` | no |
| tags | Common tags to apply to resources | `map(string)` | `{}` | no |

### clusters Object Structure

```hcl
{
  enabled                  = optional(bool, true)
  kubernetes_version       = optional(string)
  endpoint_private_access  = optional(bool, true)
  endpoint_public_access   = optional(bool, false)
  subnet_ids               = optional(list(string))
  security_group_ids       = optional(list(string), [])
  kms_key_arn              = optional(string)
  enabled_cluster_log_types = optional(list(string), ["api", "audit", "authenticator", "controllerManager", "scheduler"])
  node_groups              = optional(map(any), {})
  tags                     = optional(map(string), {})
}
```

## Outputs

| Name | Description |
|------|-------------|
| cluster_arns | Map of EKS cluster ARNs |
| cluster_endpoints | Map of EKS cluster endpoint URLs |
| cluster_security_group_ids | Map of EKS cluster security group IDs |
| cluster_certificate_authorities | Map of EKS cluster certificate authorities |
| node_group_arns | Map of EKS node group ARNs |
| oidc_providers | Map of OIDC providers for EKS clusters |

## Common Errors and Solutions

### Subnet Configuration

Error: `At least 2 subnet IDs are required for the EKS cluster to ensure high availability.`

Solution: Provide at least 2 subnet IDs across different availability zones.

### Kubernetes Version

Error: `Kubernetes version must be in the format '1.XX'`

Solution: Use a valid Kubernetes version like "1.28" or "1.29".

### Log Configuration

Error: `At least one cluster log type must be enabled`

Solution: Enable at least one log type from: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.

## Notes

- Cluster creation typically takes 15-20 minutes
- Node group creation may take an additional 5-10 minutes
- Changes to existing clusters may require careful planning
- The component uses prevent_destroy to protect against accidental deletion
- For updates to node groups, the component will try to perform rolling updates where possible