variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Short name. Compute environments and job queues are named <Environment>-<name>-<key>; the EC2 instance role and profile <Environment>-<name>-instance"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of letters, digits, underscore or hyphen."
  }
}

# Cloud Posse has no AWS Batch component or module, so the shape below is this
# repo's own: one map entry per compute environment, attribute names taken from
# the aws_batch_compute_environment compute_resources block (subnets ->
# subnet_ids, instance_type -> instance_types, as the other components name
# them). Only managed environments: unmanaged ones need an ECS cluster this
# component does not own.
variable "compute_environments" {
  type = map(object({
    # EC2 or SPOT (EC2 instances this component's launch template configures),
    # FARGATE or FARGATE_SPOT.
    type  = optional(string, "FARGATE")
    state = optional(string, "ENABLED")

    # Every type.
    max_vcpus          = optional(number)
    subnet_ids         = list(string)
    security_group_ids = list(string)

    # EC2/SPOT only: Fargate rejects these. allocation_strategy defaults to
    # BEST_FIT_PROGRESSIVE (EC2) or SPOT_PRICE_CAPACITY_OPTIMIZED (SPOT),
    # min_vcpus to 0, instance_types to ["default_x86_64"].
    allocation_strategy = optional(string)
    min_vcpus           = optional(number)
    # Leave unset: Batch rescales desired vCPUs between min and max itself, so
    # a set value drifts on every plan.
    desired_vcpus  = optional(number)
    instance_types = optional(list(string))
    # Instance profile ARN (the provider rejects a bare name, and a role ARN
    # fails at apply); null uses the profile this component creates
    # (AmazonEC2ContainerServiceforEC2Role only).
    instance_role = optional(string)
    # ECS_AL2023 (default), ECS_AL2023_NVIDIA, ECS_AL2_NVIDIA, ...; and an AMI
    # that overrides the type's latest ECS-optimized image.
    image_type        = optional(string)
    image_id_override = optional(string)
    # IMDSv2 is always required on the instances (launch template); 1 keeps
    # bridge-networked job containers off IMDS (they get credentials from the
    # job role instead). Raise only for jobs that must reach IMDS.
    metadata_http_put_response_hop_limit = optional(number)
    # Infrastructure updates (AMI, launch template, instance types) replace
    # instances; not supported with BEST_FIT.
    update_policy = optional(object({
      job_execution_timeout_minutes = optional(number, 30)
      terminate_jobs_on_update      = optional(bool, false)
    }))

    # SPOT only. spot_iam_fleet_role is required with BEST_FIT only (Spot
    # Fleet); the SPOT_* strategies and BEST_FIT_PROGRESSIVE use EC2 Fleet
    # through the Batch service-linked role.
    bid_percentage      = optional(number)
    spot_iam_fleet_role = optional(string)

    tags = optional(map(string), {})
  }))
  description = "Managed compute environments by key, named <Environment>-<name>-<key>. type is EC2, SPOT, FARGATE (default) or FARGATE_SPOT; max_vcpus, subnet_ids and security_group_ids are required for every type; the EC2/SPOT-only attributes (allocation_strategy, min/desired_vcpus, instance_types, instance_role, image_*, metadata hop limit, update_policy, bid_percentage, spot_iam_fleet_role) must be unset for Fargate. Batch runs them through the AWSServiceRoleForBatch service-linked role"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.compute_environments) : can(regex("^[a-zA-Z0-9_-]{1,64}$", k))])
    error_message = "compute_environments keys must be 1-64 characters of letters, digits, underscore or hyphen."
  }

  validation {
    condition     = alltrue([for ce in values(var.compute_environments) : contains(["EC2", "SPOT", "FARGATE", "FARGATE_SPOT"], ce.type)])
    error_message = "compute_environments type must be EC2, SPOT, FARGATE or FARGATE_SPOT."
  }

  validation {
    condition     = alltrue([for ce in values(var.compute_environments) : contains(["ENABLED", "DISABLED"], ce.state)])
    error_message = "compute_environments state must be ENABLED or DISABLED."
  }

  validation {
    condition     = alltrue([for ce in values(var.compute_environments) : ce.max_vcpus != null && try(ce.max_vcpus > 0, false)])
    error_message = "Every compute environment (Fargate included) needs max_vcpus greater than 0."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : try(length(ce.subnet_ids) > 0 && length(ce.security_group_ids) > 0, false)
    ])
    error_message = "Every compute environment needs at least one subnet_ids and one security_group_ids entry."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : !startswith(ce.type, "FARGATE") || try(length(ce.subnet_ids) <= 16, true)
    ])
    error_message = "A Fargate compute environment takes at most 16 subnet_ids."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : !startswith(ce.type, "FARGATE") || alltrue([
        ce.instance_types == null, ce.min_vcpus == null, ce.desired_vcpus == null,
        ce.allocation_strategy == null, ce.instance_role == null, ce.image_type == null,
        ce.image_id_override == null, ce.metadata_http_put_response_hop_limit == null,
        ce.update_policy == null, ce.bid_percentage == null, ce.spot_iam_fleet_role == null,
      ])
    ])
    error_message = "A FARGATE/FARGATE_SPOT compute environment takes no instance_types, min_vcpus, desired_vcpus, allocation_strategy, instance_role, image_type, image_id_override, metadata_http_put_response_hop_limit, update_policy, bid_percentage or spot_iam_fleet_role (EC2/SPOT only)."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.allocation_strategy == null || (
        ce.type == "EC2" && contains(["BEST_FIT", "BEST_FIT_PROGRESSIVE"], coalesce(ce.allocation_strategy, "-"))
        ) || (
        ce.type == "SPOT" && contains(["BEST_FIT", "BEST_FIT_PROGRESSIVE", "SPOT_CAPACITY_OPTIMIZED", "SPOT_PRICE_CAPACITY_OPTIMIZED"], coalesce(ce.allocation_strategy, "-"))
      )
    ])
    error_message = "allocation_strategy must be BEST_FIT or BEST_FIT_PROGRESSIVE for EC2, or BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED or SPOT_PRICE_CAPACITY_OPTIMIZED for SPOT."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.type != "SPOT" || ce.allocation_strategy != "BEST_FIT" || ce.spot_iam_fleet_role != null
    ])
    error_message = "A SPOT compute environment with allocation_strategy BEST_FIT needs spot_iam_fleet_role (Spot Fleet); use SPOT_PRICE_CAPACITY_OPTIMIZED (the default) to need none."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.type == "SPOT" || (ce.spot_iam_fleet_role == null && ce.bid_percentage == null)
    ])
    error_message = "spot_iam_fleet_role and bid_percentage apply to SPOT compute environments only."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.instance_role == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:instance-profile/.+$", ce.instance_role))
    ])
    error_message = "instance_role must be an instance profile ARN (arn:aws:iam::<account>:instance-profile/<name>), not a name or a role ARN."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.spot_iam_fleet_role == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", ce.spot_iam_fleet_role))
    ])
    error_message = "spot_iam_fleet_role must be an IAM role ARN."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.bid_percentage == null || try(ce.bid_percentage >= 1 && ce.bid_percentage <= 100, false)
    ])
    error_message = "bid_percentage must be between 1 and 100."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : startswith(ce.type, "FARGATE") || (
        coalesce(ce.min_vcpus, 0) >= 0
        && coalesce(ce.min_vcpus, 0) <= coalesce(ce.desired_vcpus, ce.min_vcpus, 0)
        && coalesce(ce.desired_vcpus, ce.min_vcpus, 0) <= coalesce(ce.max_vcpus, 0)
      )
    ])
    error_message = "EC2/SPOT compute environments need 0 <= min_vcpus <= desired_vcpus <= max_vcpus."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.instance_types == null || length(coalesce(ce.instance_types, [])) > 0
    ])
    error_message = "instance_types, when set, needs at least one entry (omit it for [\"default_x86_64\"])."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.metadata_http_put_response_hop_limit == null || try(ce.metadata_http_put_response_hop_limit >= 1 && ce.metadata_http_put_response_hop_limit <= 64, false)
    ])
    error_message = "metadata_http_put_response_hop_limit must be between 1 and 64."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.update_policy == null || ce.allocation_strategy != "BEST_FIT"
    ])
    error_message = "update_policy needs infrastructure updates, which BEST_FIT compute environments do not support."
  }

  validation {
    condition = alltrue([
      for ce in values(var.compute_environments) : ce.update_policy == null || try(ce.update_policy.job_execution_timeout_minutes >= 1 && ce.update_policy.job_execution_timeout_minutes <= 360, false)
    ])
    error_message = "update_policy.job_execution_timeout_minutes must be between 1 and 360."
  }
}

variable "job_queues" {
  type = map(object({
    priority = optional(number, 1)
    state    = optional(string, "ENABLED")
    # Up to 3 entries; compute_environment is a compute_environments key of
    # this instance or a compute environment ARN from elsewhere.
    compute_environment_order = list(object({
      order               = number
      compute_environment = string
    }))
    # Fair-share scheduling: creates a scheduling policy for this queue. Null
    # (default) is a FIFO queue. AWS cannot add or remove a scheduling policy
    # on an existing queue: switching between the two means a new queue key.
    fair_share_policy = optional(object({
      compute_reservation = optional(number)
      share_decay_seconds = optional(number)
      share_distribution = optional(list(object({
        share_identifier = string
        weight_factor    = optional(number)
      })), [])
    }))
    tags = optional(map(string), {})
  }))
  description = "Job queues by key, named <Environment>-<name>-<key>. priority (0-1000, higher first), state, compute_environment_order (1-3 entries, each a compute_environments key of this instance or an external compute environment ARN, all Fargate or all EC2/SPOT) and an optional fair_share_policy"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.job_queues) : can(regex("^[a-zA-Z0-9_-]{1,64}$", k))])
    error_message = "job_queues keys must be 1-64 characters of letters, digits, underscore or hyphen."
  }

  validation {
    condition     = alltrue([for q in values(var.job_queues) : q.priority >= 0 && q.priority <= 1000])
    error_message = "job_queues priority must be between 0 and 1000."
  }

  validation {
    condition     = alltrue([for q in values(var.job_queues) : contains(["ENABLED", "DISABLED"], q.state)])
    error_message = "job_queues state must be ENABLED or DISABLED."
  }

  validation {
    condition = alltrue([
      for q in values(var.job_queues) : try(length(q.compute_environment_order) >= 1 && length(q.compute_environment_order) <= 3, false)
    ])
    error_message = "Each job queue needs 1 to 3 compute_environment_order entries (not null)."
  }

  # A null compute_environment_order is reported by the 1-3 entries rule
  # above; the rules below treat it as passing (try(..., true)).
  validation {
    condition = alltrue([
      for q in values(var.job_queues) : try(
        length(distinct([for o in q.compute_environment_order : o.order])) == length(q.compute_environment_order)
        && length(distinct([for o in q.compute_environment_order : o.compute_environment])) == length(q.compute_environment_order),
        true
      )
    ])
    error_message = "A job queue's compute_environment_order entries need distinct order values and distinct compute environments."
  }

  validation {
    condition = alltrue([
      for q in values(var.job_queues) : try(alltrue([
        for o in q.compute_environment_order :
        contains(keys(var.compute_environments), o.compute_environment)
        || can(regex("^arn:aws[a-z-]*:batch:[a-z0-9-]+:[0-9]{12}:compute-environment/.+$", o.compute_environment))
      ]), true)
    ])
    error_message = "Each compute_environment_order.compute_environment must be a compute_environments key of this instance or a compute environment ARN."
  }

  validation {
    condition = alltrue([
      for q in values(var.job_queues) : try(length(distinct([
        for o in q.compute_environment_order : startswith(var.compute_environments[o.compute_environment].type, "FARGATE")
        if contains(keys(var.compute_environments), o.compute_environment)
      ])) <= 1, true)
    ])
    error_message = "A job queue cannot mix Fargate and EC2/SPOT compute environments."
  }

  validation {
    condition = alltrue([
      for q in values(var.job_queues) : q.fair_share_policy == null || alltrue([
        try(q.fair_share_policy.compute_reservation == null || (q.fair_share_policy.compute_reservation >= 0 && q.fair_share_policy.compute_reservation <= 99), false),
        try(q.fair_share_policy.share_decay_seconds == null || (q.fair_share_policy.share_decay_seconds >= 0 && q.fair_share_policy.share_decay_seconds <= 604800), false),
      ])
    ])
    error_message = "fair_share_policy compute_reservation must be 0-99 and share_decay_seconds 0-604800."
  }
}
