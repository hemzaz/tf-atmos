variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "clusters" {
  type = map(object({
    enabled                   = optional(bool, true)
    kubernetes_version        = optional(string)
    endpoint_private_access   = optional(bool, true)
    endpoint_public_access    = optional(bool, false)
    public_access_cidrs       = optional(list(string))
    subnet_ids                = optional(list(string))
    security_group_ids        = optional(list(string), [])
    kms_key_arn               = optional(string)
    enabled_cluster_log_types = optional(list(string), ["api", "audit", "authenticator", "controllerManager", "scheduler"])
    tags                      = optional(map(string), {})

    # Typed, not `map(any)`. `map(any)` forces every node group to converge on
    # one type, so a group with `taints` and a group without could not coexist:
    # "all map elements must have the same type". It also silently discarded
    # any key the component does not read.
    node_groups = optional(map(object({
      enabled        = optional(bool, true)
      instance_types = optional(list(string), ["t3.medium"])
      # instance_types and ami_type stay on the node group, never the launch
      # template: a node group accepts up to 20 instance types and a launch
      # template does not, and EKS uses ami_type to pick both the AMI and the
      # bootstrap userdata. Matches cloudposse/terraform-aws-eks-node-group.
      ami_type      = optional(string, "AL2_x86_64")
      capacity_type = optional(string, "ON_DEMAND")
      subnet_ids    = optional(list(string))
      desired_size  = optional(number, 2)
      min_size      = optional(number, 1)
      max_size      = optional(number, 4)
      labels        = optional(map(string), {})
      tags          = optional(map(string), {})
      taints = optional(list(object({
        key    = string
        value  = optional(string)
        effect = string
      })), [])
      update_config = optional(object({
        max_unavailable            = optional(number)
        max_unavailable_percentage = optional(number)
      }))

      # Launch-template instance settings, names and defaults taken from
      # cloudposse/terraform-aws-eks-node-group. IMDSv2 is required by default;
      # the hop limit of 2 lets containerized workloads assume the instance
      # profile, though IRSA service accounts are the better answer.
      detailed_monitoring_enabled          = optional(bool, false)
      metadata_http_endpoint_enabled       = optional(bool, true)
      metadata_http_put_response_hop_limit = optional(number, 2)
      metadata_http_tokens_required        = optional(bool, true)

      # Copied from cloudposse-terraform-components/aws-eks-cluster; keep in
      # sync by copy and paste. Root-volume encryption and volume type are
      # launch-template-only settings -- `aws_eks_node_group` has no argument
      # for either, and AWS rejects a node group that sets `disk_size` while a
      # launch template is attached. That is why the old `disk_size`,
      # `disk_type` and `disk_encrypted` keys are gone; upstream removed theirs
      # for the same reason. The defaults give an encrypted gp3 root volume, so
      # a stack wanting the secure baseline sets nothing.
      block_device_map = optional(map(object({
        no_device    = optional(bool, null)
        virtual_name = optional(string, null)
        ebs = optional(object({
          delete_on_termination = optional(bool, true)
          encrypted             = optional(bool, true)
          iops                  = optional(number, null)
          kms_key_id            = optional(string, null) # null => AWS-managed aws/ebs key
          snapshot_id           = optional(string, null)
          throughput            = optional(number, null) # for gp3, MiB/s, up to 1000
          volume_size           = optional(number, 50)   # disk size in GB
          volume_type           = optional(string, "gp3")

          # Catch common camel case typos. These have no effect, they just
          # generate better errors. Without these defined they would be
          # silently ignored and the default values used instead, which is
          # difficult to debug.
          deleteOnTermination = optional(any, null)
          kmsKeyId            = optional(any, null)
          snapshotId          = optional(any, null)
          volumeSize          = optional(any, null)
          volumeType          = optional(any, null)
        }))
      })), { "/dev/xvda" = { ebs = {} } })
    })), {})
  }))
  description = "Map of EKS cluster configurations with typed schema"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      v.kubernetes_version == null ||
      can(regex("^\\d+\\.(\\d+)$", v.kubernetes_version))
    ])
    error_message = "Kubernetes version must be valid and in the format 'X.Y' (e.g., 1.28)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters : length(lookup(v, "enabled_cluster_log_types", [])) > 0
    ])
    error_message = "At least one cluster log type must be enabled for each cluster."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      v.kms_key_arn == null ||
      can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", v.kms_key_arn))
    ])
    error_message = "KMS key ARN must be in a valid format (e.g., arn:aws:kms:region:account-id:key/key-id)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      alltrue([
        for sg in lookup(v, "security_group_ids", []) :
        can(regex("^sg-[a-z0-9]+$", sg))
      ])
    ])
    error_message = "All security group IDs must be in a valid format (e.g., sg-abc123)."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      lookup(v, "endpoint_private_access", true) == true || lookup(v, "endpoint_public_access", false) == true
    ])
    error_message = "At least one of endpoint_private_access or endpoint_public_access must be enabled for the cluster."
  }

  validation {
    condition = alltrue([
      for k, v in var.clusters :
      v.endpoint_public_access != true || (
        v.public_access_cidrs != null &&
        length(coalesce(v.public_access_cidrs, [])) > 0 &&
        !contains(coalesce(v.public_access_cidrs, []), "0.0.0.0/0")
      )
    ])
    error_message = "A cluster with endpoint_public_access must set public_access_cidrs to a non-empty list that does not contain 0.0.0.0/0."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the EKS clusters"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for an EKS cluster for high availability."
  }

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[a-z0-9]+$", id))])
    error_message = "All subnet IDs must be in a valid format (e.g., subnet-abc123)."
  }
}

variable "default_kubernetes_version" {
  type        = string
  description = "Default Kubernetes version for EKS clusters"
  default     = "1.28"

  validation {
    condition     = can(regex("^\\d+\\.(\\d+)$", var.default_kubernetes_version))
    error_message = "Default Kubernetes version must be in the format 'X.Y' (e.g., 1.28)."
  }
}

variable "enable_cluster_protection" {
  type        = bool
  description = "Enable EKS deletion protection for clusters in production environments"
  default     = true
}

variable "default_cluster_log_retention_days" {
  type        = number
  description = "Number of days to retain cluster logs"
  default     = 90

  # Use more maintainable validation pattern based on CloudWatch allowed values
  validation {
    # Allowed values according to CloudWatch: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    condition = (
      # Check if value is in standard retention periods (1-180 days)
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180], var.default_cluster_log_retention_days) ||
      # Or check if it's in extended periods (>180 days)
      contains([365, 400, 545, 731, 1827, 3653], var.default_cluster_log_retention_days)
    )
    error_message = "Log retention days must be a CloudWatch allowed value: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653 days."
  }

  # We can't reference var.tags here as it creates a circular reference,
  # so we'll provide guidance in the description instead
  # Better practice is to enforce this in module logic or via CI/CD validation
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}