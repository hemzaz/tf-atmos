# One cluster per component instance, as in
# cloudposse-terraform-components/aws-eks-cluster. Variable names follow that
# component (and cloudposse/terraform-aws-eks-node-group for node groups) where
# it has the setting; the rest keep this repo's names.

variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

# Cloud Posse: context `enabled`. false plans nothing (count = 0).
variable "enabled" {
  type        = bool
  description = "Set to false to create no resources"
  default     = true
}

# Cloud Posse: context `name`. Every resource is named
# "<tags.Environment>-<name>" (the repo's name_prefix convention), so `name`
# must not repeat the Environment: prod sets `main`, not `production-main`.
variable "name" {
  type        = string
  description = "Cluster name without the Environment prefix. The cluster is named <tags.Environment>-<name>."

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]*$", var.name))
    error_message = "name may only contain letters, digits, '-' and '_', because it becomes part of the EKS node group name."
  }

  validation {
    condition = (
      lower(var.name) != lower(lookup(var.tags, "Environment", "")) &&
      !startswith(lower(var.name), "${lower(lookup(var.tags, "Environment", ""))}-")
    )
    error_message = "name must not start with tags.Environment: the component already prefixes it, and repeating it doubles the Environment in every name."
  }

  # The longest name built from the prefix is the IAM role
  # "<Environment>-<name>-cluster-role"; IAM allows 64 characters.
  validation {
    condition     = length("${lookup(var.tags, "Environment", "")}-${var.name}-cluster-role") <= 64
    error_message = "<tags.Environment>-<name>-cluster-role must fit IAM's 64-character role name limit: shorten name."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the cluster and, unless a node group sets its own, its node groups"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for an EKS cluster for high availability."
  }

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[a-z0-9]+$", id))])
    error_message = "All subnet IDs must be in a valid format (e.g., subnet-abc123)."
  }
}

variable "cluster_kubernetes_version" {
  type        = string
  description = "Kubernetes version (X.Y). null lets EKS pick its default."
  default     = null

  validation {
    condition     = var.cluster_kubernetes_version == null || can(regex("^\\d+\\.(\\d+)$", var.cluster_kubernetes_version))
    error_message = "Kubernetes version must be valid and in the format 'X.Y' (e.g., 1.36)."
  }
}

# Divergence from Cloud Posse, whose default is false: this repo's clusters are
# private-endpoint first.
variable "cluster_endpoint_private_access" {
  type        = bool
  description = "Enable the private API server endpoint"
  default     = true
}

# Endpoint rules are variable validations, not resource preconditions: this
# component reads data sources, so a credential-less `terraform plan` (the
# plan sweep, CI) stops at InvalidClientTokenId before any precondition runs.
# Variable validations run before the provider authenticates.
variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Enable the public API server endpoint"
  default     = false

  validation {
    condition     = var.cluster_endpoint_private_access || var.cluster_endpoint_public_access
    error_message = "At least one of cluster_endpoint_private_access or cluster_endpoint_public_access must be enabled."
  }
}

# Divergence from Cloud Posse, whose default is ["0.0.0.0/0"]: the repo forbids
# inbound access from 0.0.0.0/0 (and ::/0), and this list is who may reach the
# API server, so a public endpoint must name its CIDRs. An empty list is not
# "no access": AWS reads it as 0.0.0.0/0.
variable "public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public endpoint; a non-empty list is required when cluster_endpoint_public_access = true"
  default     = null

  validation {
    condition = !var.cluster_endpoint_public_access || (
      var.public_access_cidrs != null ? length(var.public_access_cidrs) > 0 : false
    )
    error_message = "A public endpoint (cluster_endpoint_public_access = true) must set public_access_cidrs to a non-empty list; AWS treats an empty or missing list as 0.0.0.0/0."
  }

  # Any /0 is "everywhere": 0.0.0.0/0 and ::/0 alike. The prefix length is
  # compared as a number, so "/00" counts too. Malformed entries are left to
  # the CIDR validation below (try() keeps this one from erroring).
  validation {
    condition = var.public_access_cidrs == null ? true : alltrue([
      for c in var.public_access_cidrs : try(tonumber(split("/", c)[1]) != 0, true)
    ])
    error_message = "public_access_cidrs must not contain a /0 range (0.0.0.0/0 or ::/0)."
  }

  validation {
    condition     = var.public_access_cidrs == null ? true : alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "Every public_access_cidrs entry must be a CIDR block (e.g., 203.0.113.0/24)."
  }
}

# cloudposse/terraform-aws-eks-cluster: associated_security_group_ids.
variable "associated_security_group_ids" {
  type        = list(string)
  description = "Additional security groups attached to the cluster's ENIs (vpc_config.security_group_ids)"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for sg in var.associated_security_group_ids : can(regex("^sg-[a-z0-9]+$", sg))])
    error_message = "All security group IDs must be in a valid format (e.g., sg-abc123)."
  }
}

variable "cluster_encryption_config_kms_key_id" {
  type        = string
  description = "KMS key ARN for secrets encryption. Empty uses the key this component creates."
  default     = ""
  nullable    = false

  validation {
    condition     = var.cluster_encryption_config_kms_key_id == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.cluster_encryption_config_kms_key_id))
    error_message = "KMS key ARN must be in a valid format (e.g., arn:aws:kms:region:account-id:key/key-id)."
  }
}

# Divergence from Cloud Posse, whose default is []: all control-plane logs on.
variable "enabled_cluster_log_types" {
  type        = list(string)
  description = "Control plane log types to enable"
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  nullable    = false

  validation {
    condition     = length(var.enabled_cluster_log_types) > 0
    error_message = "At least one cluster log type must be enabled."
  }

  validation {
    condition     = alltrue([for t in var.enabled_cluster_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "Log types must be among api, audit, authenticator, controllerManager and scheduler."
  }
}

# Cloud Posse name (its default is 0, never expire). 7 by owner decision;
# prod pins 90.
variable "cluster_log_retention_period" {
  type        = number
  description = "Days to retain control plane logs"
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cluster_log_retention_period)
    error_message = "Log retention days must be a CloudWatch allowed value."
  }
}

variable "enable_cluster_protection" {
  type        = bool
  description = "Enable EKS deletion protection when tags.Environment is prod or production"
  default     = true
}

# Node groups: a map, one entry per group, field names as in
# cloudposse-terraform-components/aws-eks-cluster where it has the field.
# The disk_* and camel-case block_device_map attributes are declared only so
# the validations below can reject them; an undeclared attribute would be
# dropped silently by the type constraint.
# Deviation from Cloud Posse: cloudposse/terraform-aws-eks-node-group defaults
# ami_type to AL2_x86_64 (aws-eks-cluster leaves it null). AWS publishes no AL2
# EKS AMIs for Kubernetes 1.33 and later, and the stacks pin 1.36, so the
# default here is AL2023_x86_64_STANDARD.
variable "node_groups" {
  type = map(object({
    enabled            = optional(bool, true)
    instance_types     = optional(list(string), ["t3.medium"])
    ami_type           = optional(string, "AL2023_x86_64_STANDARD")
    capacity_type      = optional(string, "ON_DEMAND")
    subnet_ids         = optional(list(string))
    desired_group_size = optional(number, 2)
    min_group_size     = optional(number, 1)
    max_group_size     = optional(number, 4)
    kubernetes_labels  = optional(map(string), {})
    tags               = optional(map(string), {})
    kubernetes_taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    update_config = optional(object({
      max_unavailable            = optional(number)
      max_unavailable_percentage = optional(number)
    }))

    detailed_monitoring_enabled          = optional(bool, false)
    metadata_http_endpoint_enabled       = optional(bool, true)
    metadata_http_put_response_hop_limit = optional(number, 2)
    metadata_http_tokens_required        = optional(bool, true)
    random_pet_length                    = optional(number, 1)
    immediately_apply_lt_changes         = optional(bool, null)

    block_device_map = optional(map(object({
      no_device    = optional(bool, null)
      virtual_name = optional(string, null)
      ebs = optional(object({
        delete_on_termination = optional(bool, true)
        encrypted             = optional(bool, true)
        iops                  = optional(number, null)
        kms_key_id            = optional(string, null)
        snapshot_id           = optional(string, null)
        throughput            = optional(number, null)
        volume_size           = optional(number, 50)
        volume_type           = optional(string, "gp3")

        deleteOnTermination = optional(any, null)
        kmsKeyId            = optional(any, null)
        snapshotId          = optional(any, null)
        volumeSize          = optional(any, null)
        volumeType          = optional(any, null)
      }))
    })), { "/dev/xvda" = { ebs = {} } })

    disk_size               = optional(any, null)
    disk_type               = optional(any, null)
    disk_encrypted          = optional(any, null)
    disk_encryption_enabled = optional(any, null)
  }))
  description = "Managed node groups of this cluster, keyed by node group name"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, ng in var.node_groups : can(regex("^[0-9A-Za-z][0-9A-Za-z_-]*$", k))])
    error_message = "Node group keys may only contain letters, digits, '-' and '_'."
  }

  # AWS publishes no Amazon Linux 2 EKS AMIs for Kubernetes 1.33 and later
  # (docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-extended.html,
  # the 1.32 notes), so an AL2_* node group on such a cluster cannot be created.
  validation {
    condition = alltrue([for k, ng in var.node_groups :
      !startswith(ng.ami_type, "AL2_") || var.cluster_kubernetes_version == null ? true : (
        tonumber(split(".", var.cluster_kubernetes_version)[0]) == 1 && tonumber(split(".", var.cluster_kubernetes_version)[1]) < 33
      )
    ])
    error_message = "AL2_* AMI types are not available for Kubernetes 1.33 and later: use an AL2023_* or BOTTLEROCKET_* ami_type (default AL2023_x86_64_STANDARD)."
  }

  validation {
    condition     = alltrue([for k, ng in var.node_groups : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for k, ng in var.node_groups : ng.metadata_http_put_response_hop_limit >= 1])
    error_message = "metadata_http_put_response_hop_limit must be at least 1; IMDS is unreachable below that."
  }

  validation {
    condition = alltrue([for k, ng in var.node_groups :
    ng.min_group_size <= ng.desired_group_size && ng.desired_group_size <= ng.max_group_size])
    error_message = "Each node group must satisfy min_group_size <= desired_group_size <= max_group_size."
  }

  validation {
    condition = alltrue([for k, ng in var.node_groups : length(compact(flatten([
      for device_name, device in ng.block_device_map : [
        device.ebs.deleteOnTermination, device.ebs.kmsKeyId, device.ebs.snapshotId,
        device.ebs.volumeSize, device.ebs.volumeType,
      ] if device.ebs != null
    ]))) == 0])
    error_message = "block_device_map does not support the camel case arguments deleteOnTermination, kmsKeyId, snapshotId, volumeSize or volumeType."
  }

  validation {
    condition = alltrue([for k, ng in var.node_groups : length(compact([
      for x in [ng.disk_size, ng.disk_type, ng.disk_encrypted, ng.disk_encryption_enabled] : x == null ? "" : "set"
    ])) == 0])
    error_message = "Node groups no longer accept disk_size, disk_type, disk_encrypted or disk_encryption_enabled. Use block_device_map."
  }

  validation {
    condition     = alltrue([for k, ng in var.node_groups : ng.random_pet_length >= 1 && floor(ng.random_pet_length) == ng.random_pet_length])
    error_message = "random_pet_length must be a whole number of at least 1."
  }

  validation {
    condition = alltrue([for k, ng in var.node_groups : alltrue([
      for t in ng.kubernetes_taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
    ])])
    error_message = "Taint effect must be one of: NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }

  # EKS allows 63 characters for a node group name, "<name_base>-<pet>". The
  # pet is at most 9 characters ("-" included) per word up to two words and 11
  # per adverb beyond. A validation may read other variables since Terraform
  # 1.9, so name_base is spelled out as local.node_groups builds it.
  validation {
    condition = alltrue([for k, ng in var.node_groups :
      length("${lookup(var.tags, "Environment", "")}-${var.name}-${k}") <= 63 - (9 * min(ng.random_pet_length, 2) + 11 * max(ng.random_pet_length - 2, 0))
      if ng.enabled
    ])
    error_message = "Node group names are limited to 63 characters by EKS including the random_pet suffix: shorten name or the node group key."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources. Environment is required: it prefixes every name."

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}
