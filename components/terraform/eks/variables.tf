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
# must not repeat the Environment: prod sets `main`, not `ue1-main`.
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

# cloudposse/terraform-aws-eks-cluster: allowed_security_group_ids and
# allowed_cidr_blocks (same names, types and defaults; the aws-eks-cluster
# component calls the first allowed_security_groups). Each entry becomes an
# ingress rule on the EKS-managed cluster security group, TCP 443 only
# (security-group.tf).
variable "allowed_security_group_ids" {
  type        = list(string)
  description = "IDs of security groups allowed to reach the Kubernetes API (TCP 443) through the EKS-managed cluster security group"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", sg))])
    error_message = "Every allowed_security_group_ids entry must be a security group ID (e.g., sg-0123456789abcdef0)."
  }
}

# IPv4 only, as upstream (cidr_ipv4). The repo forbids inbound 0.0.0.0/0, so
# any /0 is rejected; the prefix length is compared as a number ("/00" too).
variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to reach the Kubernetes API (TCP 443) through the EKS-managed cluster security group. The length must be known at plan time"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0)) && can(regex("^[0-9.]+/[0-9]+$", c))])
    error_message = "Every allowed_cidr_blocks entry must be an IPv4 CIDR block (e.g., 10.20.0.0/16)."
  }

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : try(tonumber(split("/", c)[1]) != 0, true)])
    error_message = "allowed_cidr_blocks must not contain a /0 range (0.0.0.0/0)."
  }
}

variable "cluster_encryption_config_kms_key_id" {
  type        = string
  description = "KMS key ARN for secrets encryption. Empty uses the key this component creates."
  default     = ""
  nullable    = false

  validation {
    condition     = var.cluster_encryption_config_kms_key_id == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-)?[a-f0-9-]+$", var.cluster_encryption_config_kms_key_id))
    error_message = "KMS key ARN must be in a valid format (e.g., arn:aws:kms:region:account-id:key/key-id)."
  }
}

# cloudposse/terraform-aws-eks-node-group: a launch template's block_device_map
# is the only way to control a managed node group's root-volume encryption
# key. This is the *default* for a device that sets no ebs.kms_key_id of its
# own; a device-level value always wins.
variable "node_group_ebs_kms_key_id" {
  type        = string
  description = "Default KMS key ARN for a node group's block_device_map EBS volumes whose ebs.kms_key_id is not set. Empty leaves such volumes on the AWS managed aws/ebs key. Whichever key is used needs a policy granting the AWSServiceRoleForAutoScaling service-linked role kms:CreateGrant (kms:GrantIsForAWSResource) plus Encrypt/Decrypt/ReEncrypt*/GenerateDataKey*/DescribeKey (kms/main's allow_autoscaling_ebs), or new instances fail to launch."
  default     = ""
  nullable    = false

  validation {
    condition     = var.node_group_ebs_kms_key_id == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-)?[a-f0-9-]+$", var.node_group_ebs_kms_key_id))
    error_message = "node_group_ebs_kms_key_id must be a valid KMS key ARN (e.g., arn:aws:kms:region:account-id:key/key-id)."
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
  description = "Enable EKS deletion protection when tags.Stage is prod or production"
  default     = true
}

# Node groups: a map, one entry per group, field names as in
# cloudposse-terraform-components/aws-eks-cluster where it has the field.
# The disk_* and camel-case block_device_map attributes are declared only so
# the validations below can reject them; an undeclared attribute would be
# dropped silently by the type constraint.
# Deviation from Cloud Posse (2): metadata_http_put_response_hop_limit
# defaults to 1, as the ec2 component's does. Pods reach AWS through IRSA
# (vpc-cni included, addons.tf), so no container off the host network needs
# IMDS; a node group that does sets 2.
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
    metadata_http_put_response_hop_limit = optional(number, 1)
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

# ---------------------------------------------------------------------------
# Access: cloudposse/terraform-aws-eks-cluster's access_config,
# access_entry_map, access_entries and access_policy_associations, same types
# and defaults. See auth.tf.
# The access policies the validations accept are the EKS access policies for
# people and CI (`aws eks list-access-policies`); extend the lists when one
# is needed. A policy may be given as its short name (Admin, ClusterAdmin,
# Edit, View), its full name, or its ARN.
# ---------------------------------------------------------------------------

variable "access_config" {
  type = object({
    authentication_mode                         = optional(string, "API")
    bootstrap_cluster_creator_admin_permissions = optional(bool, false)
  })
  description = "Access configuration for the EKS cluster: API authentication mode (access entries) and no implicit cluster-creator admin by default"
  default     = {}
  nullable    = false

  # Cloud Posse rejects CONFIG_MAP; this also rejects anything else AWS would.
  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.access_config.authentication_mode)
    error_message = "access_config.authentication_mode must be API or API_AND_CONFIG_MAP; the CONFIG_MAP authentication_mode is not supported."
  }
}

variable "access_entry_map" {
  type = map(object({
    # key is principal_arn
    user_name = optional(string)
    # Cannot assign "system:*" groups to IAM users, use ClusterAdmin and Admin instead
    kubernetes_groups = optional(list(string), [])
    type              = optional(string, "STANDARD")
    access_policy_associations = optional(map(object({
      # key is policy_arn or policy_name
      access_scope = optional(object({
        type       = optional(string, "cluster")
        namespaces = optional(list(string))
      }), {}) # access_scope
    })), {})  # access_policy_associations
  }))         # access_entry_map
  description = <<-EOT
    Map of IAM Principal ARNs to access configuration.
    Preferred over the list inputs as this configuration remains stable when
    elements are added or removed, but the keys must be known at plan time and
    written literally: an Atmos YAML function cannot produce a map key, so a
    principal read with !terraform.state goes in access_entries instead.
    Map `access_policy_associations` keys are policy ARNs, policy
    full name (AmazonEKSViewPolicy), or short name (View).
    Membership in `system:masters` becomes an association with the ClusterAdmin
    policy; any other `system:*` group is rejected.
    EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.access_entry_map : contains(["STANDARD", "EC2_LINUX", "EC2_WINDOWS"], v.type)])
    error_message = "access_entry_map type must be STANDARD, EC2_LINUX or EC2_WINDOWS."
  }

  # EKS (CreateAccessEntry API reference; user guide "Create access
  # entries"): only a STANDARD entry may set kubernetesGroups or a username,
  # or have access policies associated. Cloud Posse's access_entry_map passes
  # such an entry through and the apply fails; here the plan does. (Its node
  # entries, access_entries_for_nodes, set none of them.)
  validation {
    condition = alltrue([for k, v in var.access_entry_map :
      v.type == "STANDARD" || (length(v.kubernetes_groups) == 0 && v.user_name == null && length(v.access_policy_associations) == 0)
    ])
    error_message = "An access_entry_map entry whose type is not STANDARD (EC2_LINUX, EC2_WINDOWS) may not set kubernetes_groups, user_name or access_policy_associations: EKS rejects them."
  }

  validation {
    condition = alltrue([for k, v in var.access_entry_map : alltrue([
      for g in v.kubernetes_groups : g == "system:masters" || !startswith(g, "system:")
    ])])
    error_message = "access_entry_map kubernetes_groups may not contain system:* groups other than system:masters; use the Admin or ClusterAdmin access policy."
  }

  validation {
    condition = alltrue(flatten([for k, v in var.access_entry_map : [
      for p, a in v.access_policy_associations : contains(concat(
        ["Admin", "ClusterAdmin", "Edit", "View"],
        ["AmazonEKSAdminPolicy", "AmazonEKSAdminViewPolicy", "AmazonEKSClusterAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy", "AmazonEMRJobPolicy"],
        [for n in ["AmazonEKSAdminPolicy", "AmazonEKSAdminViewPolicy", "AmazonEKSClusterAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy", "AmazonEMRJobPolicy"] : "arn:aws:eks::aws:cluster-access-policy/${n}"],
      ), p)
    ]]))
    error_message = "access_entry_map access_policy_associations keys must be EKS access policies: Admin, ClusterAdmin, Edit, View, AmazonEKSAdminPolicy, AmazonEKSAdminViewPolicy, AmazonEKSClusterAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy or AmazonEMRJobPolicy (name or arn:aws:eks::aws:cluster-access-policy/<name>)."
  }

  validation {
    condition = alltrue(flatten([for k, v in var.access_entry_map : [
      for p, a in v.access_policy_associations : contains(["cluster", "namespace"], a.access_scope.type)
    ]]))
    error_message = "access_scope.type must be cluster or namespace."
  }

  validation {
    condition = alltrue(flatten([for k, v in var.access_entry_map : [
      for p, a in v.access_policy_associations : a.access_scope.type == "namespace" ? length(coalesce(a.access_scope.namespaces, [])) > 0 : length(coalesce(a.access_scope.namespaces, [])) == 0
    ]]))
    error_message = "An access_scope of type namespace must list its namespaces; one of type cluster must not."
  }
}

variable "access_entries" {
  type = list(object({
    principal_arn     = string
    user_name         = optional(string, null)
    kubernetes_groups = optional(list(string), null)
  }))
  description = <<-EOT
    List of IAM principals to allow to access the EKS cluster (STANDARD access entries).
    Use when the Principal ARN is not known at plan time or comes from an Atmos
    YAML function. An entry whose principal_arn is null (an optional role that
    is not created) is skipped.
    EOT
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for e in var.access_entries : alltrue([
      for g in coalesce(e.kubernetes_groups, []) : !startswith(g, "system:")
    ])])
    error_message = "access_entries kubernetes_groups may not contain system:* groups; use the Admin or ClusterAdmin access policy."
  }
}

variable "access_policy_associations" {
  type = list(object({
    principal_arn = string
    policy_arn    = string
    access_scope = optional(object({
      type       = optional(string, "cluster")
      namespaces = optional(list(string))
    }), {})
  }))
  description = <<-EOT
    List of AWS managed EKS access policies to associate with IAM principals.
    Use when the Principal ARN or Policy ARN is not known at plan time.
    `policy_arn` can be the full ARN, the full name (AmazonEKSViewPolicy) or short name (View).
    An association whose principal_arn is null is skipped, as in access_entries.
    EOT
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for a in var.access_policy_associations : contains(concat(
      ["Admin", "ClusterAdmin", "Edit", "View"],
      ["AmazonEKSAdminPolicy", "AmazonEKSAdminViewPolicy", "AmazonEKSClusterAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy", "AmazonEMRJobPolicy"],
      [for n in ["AmazonEKSAdminPolicy", "AmazonEKSAdminViewPolicy", "AmazonEKSClusterAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy", "AmazonEMRJobPolicy"] : "arn:aws:eks::aws:cluster-access-policy/${n}"],
    ), a.policy_arn)])
    error_message = "access_policy_associations policy_arn must be an EKS access policy: Admin, ClusterAdmin, Edit, View, AmazonEKSAdminPolicy, AmazonEKSAdminViewPolicy, AmazonEKSClusterAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy or AmazonEMRJobPolicy (name or arn:aws:eks::aws:cluster-access-policy/<name>)."
  }

  validation {
    condition     = alltrue([for a in var.access_policy_associations : contains(["cluster", "namespace"], a.access_scope.type)])
    error_message = "access_scope.type must be cluster or namespace."
  }

  validation {
    condition = alltrue([for a in var.access_policy_associations :
      a.access_scope.type == "namespace" ? length(coalesce(a.access_scope.namespaces, [])) > 0 : length(coalesce(a.access_scope.namespaces, [])) == 0
    ])
    error_message = "An access_scope of type namespace must list its namespaces; one of type cluster must not."
  }
}

# Cloud Posse's eks/cluster component input (cloudposse-terraform-components/
# aws-eks-cluster, src/variables.tf and src/main.tf iam_roles_access_entry_map),
# same name and type. Each role becomes an access_entry_map entry with `groups`
# as its kubernetes_groups, so `system:masters` becomes a cluster-scoped
# AmazonEKSClusterAdminPolicy association (auth.tf). As upstream, `username`
# is accepted and ignored. The stacks list their human admin roles here
# (stacks/orgs/fnx/<stage>/<region>/<stack>/components/globals.yaml).
variable "map_additional_iam_roles" {
  type = list(object({
    rolearn  = string
    username = optional(string)
    groups   = list(string)
  }))
  description = <<-EOT
    Additional IAM roles to grant access to the cluster, as in Cloud Posse's eks/cluster component.
    `rolearn` is the full role ARN INCLUDING its path: access entries (unlike the old aws-auth
    ConfigMap) require it, and the IAM Identity Center role of a permission set lives under
    /aws-reserved/sso.amazonaws.com/[<sso-region>/] (the Identity Center home region), e.g.
    arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<sso-region>/AWSReservedSSO_AdministratorAccess_<hash>
    (`aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`).
    `groups` = ["system:masters"] grants a cluster-scoped AmazonEKSClusterAdminPolicy association.
    `username` is ignored. Keys of access_entry_map win over a role listed here.
    EOT
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for r in var.map_additional_iam_roles :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/([\\w+=,.@-]+/)*[\\w+=,.@-]+$", r.rolearn))
    ])
    error_message = "map_additional_iam_roles rolearn must be an IAM role ARN, arn:aws:iam::<12-digit account>:role/[<path>/]<name> (no empty path segment or trailing /); not an sts assumed-role ARN, a user or a wildcard."
  }

  validation {
    condition = alltrue([for r in var.map_additional_iam_roles :
      !strcontains(r.rolearn, ":role/aws-service-role/")
    ])
    error_message = "map_additional_iam_roles rolearn may not be a service-linked role (role/aws-service-role/...): EKS access entries do not support them."
  }

  # The aws-auth habit of stripping the path names a role that does not
  # exist: the access entry fails to create and the backend's aws:PrincipalArn
  # trust never matches.
  validation {
    condition = alltrue([for r in var.map_additional_iam_roles :
      !startswith(element(split("/", r.rolearn), length(split("/", r.rolearn)) - 1), "AWSReservedSSO_") ||
      can(regex(":role/aws-reserved/sso\\.amazonaws\\.com/([a-z]{2}(-[a-z]+)+-[0-9]/)?AWSReservedSSO_[\\w+=,.@-]+_[0-9a-f]{16}$", r.rolearn))
    ])
    error_message = "An IAM Identity Center role (AWSReservedSSO_<permission set>_<16 hex>) must keep its path: arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/[<region>/]AWSReservedSSO_<permission set>_<hash>."
  }

  validation {
    condition     = length(distinct([for r in var.map_additional_iam_roles : r.rolearn])) == length(var.map_additional_iam_roles)
    error_message = "map_additional_iam_roles lists a rolearn more than once."
  }

  validation {
    condition = alltrue([for r in var.map_additional_iam_roles : alltrue([
      for g in r.groups : g == "system:masters" || !startswith(g, "system:")
    ])])
    error_message = "map_additional_iam_roles groups may not contain system:* groups other than system:masters."
  }
}

# cloudposse/terraform-aws-eks-cluster: upgrade_policy. Divergence: Cloud
# Posse defaults to null, which AWS treats as EXTENDED; STANDARD fails closed
# against extended-support charges once a version leaves standard support.
variable "upgrade_policy" {
  type = object({
    support_type = optional(string, "STANDARD")
  })
  description = "Support policy for the cluster: STANDARD (default; the cluster is auto-upgraded at the end of standard support) or EXTENDED (paid extended support)"
  default     = {}
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.upgrade_policy.support_type)
    error_message = "upgrade_policy.support_type must be STANDARD or EXTENDED."
  }
}

# The vpc-cni managed addon (addons.tf). Fields are an entry of Cloud Posse's
# aws-eks-cluster `addons` map; vpc-cni is always installed, because the node
# role carries no CNI policy. service_account_role_arn null (the default)
# makes this component create the IRSA role, as Cloud Posse does.
variable "vpc_cni_addon" {
  type = object({
    addon_version               = optional(string, null)
    configuration_values        = optional(string, null)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string, null)
    create_timeout              = optional(string, null)
    update_timeout              = optional(string, null)
    delete_timeout              = optional(string, null)
    preserve                    = optional(bool, true)
  })
  description = "The vpc-cni EKS managed addon: version (null: the EKS default for the cluster version), configuration JSON, conflict resolution, and an optional existing IRSA role"
  default     = {}
  nullable    = false

  validation {
    condition     = contains(["NONE", "OVERWRITE"], var.vpc_cni_addon.resolve_conflicts_on_create) && contains(["NONE", "OVERWRITE", "PRESERVE"], var.vpc_cni_addon.resolve_conflicts_on_update)
    error_message = "vpc_cni_addon.resolve_conflicts_on_create must be NONE or OVERWRITE; resolve_conflicts_on_update NONE, OVERWRITE or PRESERVE."
  }

  validation {
    condition     = var.vpc_cni_addon.service_account_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.vpc_cni_addon.service_account_role_arn))
    error_message = "vpc_cni_addon.service_account_role_arn must be an IAM role ARN."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources. Environment is required: it prefixes every name. Stage is required: prod gets deletion protection."

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }

  # The tier, from settings.context.stage. Required: Environment is the region
  # code (ue1), so nothing else says whether this is production.
  validation {
    condition     = trimspace(lookup(var.tags, "Stage", "")) != ""
    error_message = "tags must include a non-empty Stage value (settings.context.stage)."
  }
}
