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

# Container job definitions, one map entry each. Cloud Posse has no Batch
# module, so container_properties is built from typed attributes (not raw
# JSON) so the roles, the log group and the Fargate/EC2 rules can be derived
# and validated here.
variable "job_definitions" {
  type = map(object({
    # EC2 (also runs on SPOT environments) or FARGATE (also FARGATE_SPOT).
    platform_capability = optional(string, "FARGATE")

    image = string
    # vCPUs and memory (MiB), sent as resourceRequirements. Fargate takes the
    # documented combinations only (0.25-16 vCPU); EC2 whole vCPUs >= 1 and
    # memory >= 4 MiB. gpu is EC2 only.
    vcpu   = number
    memory = number
    gpu    = optional(number)

    command = optional(list(string), [])
    # Default values for Ref::<name> placeholders in command.
    parameters  = optional(map(string), {})
    environment = optional(map(string), {})
    # Environment variable name -> Secrets Manager secret ARN (the full ARN
    # with its 6-character suffix, optionally :json-key:version-stage:version-id)
    # or SSM parameter ARN. The execution role is granted exactly these.
    secrets = optional(map(string), {})

    # Job role (what the job's code may call). Unset with no policies, the job
    # runs without AWS credentials. job_role_policy_arns and/or
    # job_role_policy_json create <Environment>-<name>-<key>-job; job_role_arn
    # uses an existing role instead (and excludes both).
    job_role_arn         = optional(string)
    job_role_policy_arns = optional(list(string), [])
    job_role_policy_json = optional(string)

    # FARGATE only. The platform version defaults to LATEST, assign_public_ip
    # to DISABLED (ENABLED only for public subnets without NAT), ephemeral
    # storage to Fargate's 20 GiB, cpu_architecture to X86_64.
    fargate_platform_version = optional(string)
    assign_public_ip         = optional(string)
    ephemeral_storage_gib    = optional(number)
    cpu_architecture         = optional(string)

    readonly_root_filesystem = optional(bool, true)
    # EC2 only: Fargate rejects privileged containers.
    privileged = optional(bool, false)
    user       = optional(string)
    # EC2 only.
    ulimits = optional(list(object({
      name       = string
      soft_limit = number
      hard_limit = number
    })), [])
    # init_process_enabled works on both; shared_memory_size (MiB) and devices
    # are EC2 only.
    linux_parameters = optional(object({
      init_process_enabled = optional(bool)
      shared_memory_size   = optional(number)
      devices = optional(list(object({
        host_path      = string
        container_path = optional(string)
        permissions    = optional(list(string))
      })), [])
    }))

    # awslogs to the component's /aws/batch/<Environment>-<name> log group;
    # the stream prefix defaults to the key.
    log_stream_prefix = optional(string)

    retry_strategy = optional(object({
      attempts = optional(number, 1)
      evaluate_on_exit = optional(list(object({
        action           = string
        on_exit_code     = optional(string)
        on_reason        = optional(string)
        on_status_reason = optional(string)
      })), [])
    }), {})
    timeout_seconds     = optional(number)
    propagate_tags      = optional(bool, true)
    scheduling_priority = optional(number)

    tags = optional(map(string), {})
  }))
  description = "Container job definitions by key, named <Environment>-<name>-<key>: platform_capability (FARGATE default, or EC2), image, vcpu, memory (MiB), gpu (EC2), command, parameters, environment, secrets (env name -> Secrets Manager or SSM parameter ARN), a job role (job_role_arn, or job_role_policy_arns/job_role_policy_json to create one), Fargate settings (fargate_platform_version, assign_public_ip DISABLED by default, ephemeral_storage_gib, cpu_architecture), readonly_root_filesystem (default true), privileged (EC2 only), user, ulimits (EC2), linux_parameters, log_stream_prefix, retry_strategy (1-10 attempts, evaluate_on_exit), timeout_seconds (>= 60), propagate_tags (default true), scheduling_priority and tags. Every change registers a new revision"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.job_definitions) : can(regex("^[a-zA-Z0-9_-]{1,64}$", k))])
    error_message = "job_definitions keys must be 1-64 characters of letters, digits, underscore or hyphen."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : contains(["EC2", "FARGATE"], d.platform_capability)])
    error_message = "job_definitions platform_capability must be EC2 or FARGATE."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : try(trimspace(d.image) != "", false)])
    error_message = "Every job definition needs a non-empty image."
  }

  # Fargate's documented vCPU/memory (MiB) combinations.
  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : d.platform_capability != "FARGATE" || contains(lookup({
        "0.25" = [512, 1024, 2048]
        "0.5"  = range(1024, 4097, 1024)
        "1"    = range(2048, 8193, 1024)
        "2"    = range(4096, 16385, 1024)
        "4"    = range(8192, 30721, 1024)
        "8"    = range(16384, 61441, 4096)
        "16"   = range(32768, 122881, 8192)
      }, tostring(d.vcpu), []), d.memory)
    ])
    error_message = "A FARGATE job definition needs a supported vcpu/memory (MiB) pair: 0.25 vCPU with 512, 1024 or 2048; 0.5 with 1024-4096; 1 with 2048-8192; 2 with 4096-16384; 4 with 8192-30720 (1024 steps); 8 with 16384-61440 (4096 steps); 16 with 32768-122880 (8192 steps)."
  }

  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : d.platform_capability != "EC2" || (
        d.vcpu >= 1 && floor(d.vcpu) == d.vcpu && d.memory >= 4 && floor(d.memory) == d.memory
      )
    ])
    error_message = "An EC2 job definition needs a whole vcpu of at least 1 and a whole memory (MiB) of at least 4."
  }

  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : d.platform_capability == "EC2" || alltrue([
        d.gpu == null, !d.privileged, length(d.ulimits) == 0,
        try(d.linux_parameters.shared_memory_size, null) == null,
        length(try(d.linux_parameters.devices, [])) == 0,
      ])
    ])
    error_message = "A FARGATE job definition takes no gpu, privileged, ulimits, linux_parameters.shared_memory_size or linux_parameters.devices (EC2 only)."
  }

  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : d.platform_capability == "FARGATE" || alltrue([
        d.fargate_platform_version == null, d.assign_public_ip == null,
        d.ephemeral_storage_gib == null, d.cpu_architecture == null,
      ])
    ])
    error_message = "fargate_platform_version, assign_public_ip, ephemeral_storage_gib and cpu_architecture apply to FARGATE job definitions only."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.gpu == null || try(d.gpu >= 1 && floor(d.gpu) == d.gpu, false)])
    error_message = "gpu must be a whole number of at least 1."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : contains(["ENABLED", "DISABLED"], coalesce(d.assign_public_ip, "DISABLED"))])
    error_message = "assign_public_ip must be ENABLED or DISABLED."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : contains(["X86_64", "ARM64"], coalesce(d.cpu_architecture, "X86_64"))])
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.ephemeral_storage_gib == null || try(d.ephemeral_storage_gib >= 21 && d.ephemeral_storage_gib <= 200, false)])
    error_message = "ephemeral_storage_gib must be between 21 and 200 (unset is Fargate's 20 GiB)."
  }

  validation {
    condition = alltrue(flatten([
      for d in values(var.job_definitions) : [
        for n, arn in d.secrets : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", n)) && (
          can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[^:]+(:[^:]*:[^:]*:[^:]*)?$", arn)) ||
          can(regex("^arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{12}:parameter/.+$", arn))
        )
      ]
    ]))
    error_message = "secrets maps an environment variable name to a Secrets Manager secret ARN (arn:aws:secretsmanager:<region>:<account>:secret:<name>-<suffix>, optionally :<json-key>:<version-stage>:<version-id>) or an SSM parameter ARN (arn:aws:ssm:<region>:<account>:parameter/<name>). Names are rejected: the execution role is scoped to the ARNs."
  }

  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : d.job_role_arn == null || (length(d.job_role_policy_arns) == 0 && d.job_role_policy_json == null)
    ])
    error_message = "job_role_arn uses an existing role: leave job_role_policy_arns and job_role_policy_json unset with it."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.job_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", d.job_role_arn))])
    error_message = "job_role_arn must be an IAM role ARN."
  }

  validation {
    condition = alltrue(flatten([
      for d in values(var.job_definitions) : [for a in d.job_role_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", a))]
    ]))
    error_message = "job_role_policy_arns entries must be IAM policy ARNs."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.job_role_policy_json == null || can(jsondecode(d.job_role_policy_json).Statement)])
    error_message = "job_role_policy_json must be an IAM policy document (JSON with a Statement)."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : try(d.retry_strategy.attempts >= 1 && d.retry_strategy.attempts <= 10, false)])
    error_message = "retry_strategy.attempts must be between 1 and 10."
  }

  validation {
    condition = alltrue([
      for d in values(var.job_definitions) : try(length(d.retry_strategy.evaluate_on_exit) <= 5 && alltrue([
        for e in d.retry_strategy.evaluate_on_exit :
        contains(["RETRY", "EXIT"], e.action) && anytrue([e.on_exit_code != null, e.on_reason != null, e.on_status_reason != null])
      ]), false)
    ])
    error_message = "retry_strategy.evaluate_on_exit takes up to 5 entries, each with action RETRY or EXIT and at least one of on_exit_code, on_reason or on_status_reason."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.timeout_seconds == null || try(d.timeout_seconds >= 60, false)])
    error_message = "timeout_seconds (the attempt duration) must be at least 60."
  }

  validation {
    condition     = alltrue([for d in values(var.job_definitions) : d.scheduling_priority == null || try(d.scheduling_priority >= 0 && d.scheduling_priority <= 9999, false)])
    error_message = "scheduling_priority must be between 0 and 9999 (it only applies on fair-share queues)."
  }
}

# Cloud Posse ecs-service pattern: the component creates the execution role
# unless it is given one.
variable "execution_role_arn" {
  type        = string
  description = "Existing ECS task execution role for the job definitions that need one (FARGATE, or any with secrets). Null creates <Environment>-<name>-job-execution, scoped to the component's log group, ecr_repository_arns, the definitions' secrets and secrets_kms_key_arn"
  default     = null

  validation {
    condition     = var.execution_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.execution_role_arn))
    error_message = "execution_role_arn must be an IAM role ARN."
  }
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repositories the created execution role may pull from (FARGATE jobs; EC2 jobs pull with the instance role). Empty allows every repository (\"*\"), as AmazonECSTaskExecutionRolePolicy does"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", a))])
    error_message = "ecr_repository_arns entries must be ECR repository ARNs (arn:aws:ecr:<region>:<account>:repository/<name>)."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Customer managed KMS key encrypting the definitions' secrets (Secrets Manager secrets, SecureString parameters). The created execution role gets kms:Decrypt on it through Secrets Manager and SSM only. Null for AWS managed keys"
  default     = null

  validation {
    condition     = var.secrets_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.secrets_kms_key_arn))
    error_message = "secrets_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "log_kms_key_arn" {
  type        = string
  description = "KMS key ARN (the stack's kms/main .key_arn) encrypting the job log group /aws/batch/<Environment>-<name>; its policy must allow logs.<region>.amazonaws.com (kms allow_cloudwatch_logs). Required when job_definitions is not empty"
  default     = null

  validation {
    condition     = var.log_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }

  validation {
    condition     = var.log_kms_key_arn != null || length(var.job_definitions) == 0
    error_message = "job_definitions need log_kms_key_arn (kms/main .key_arn) for their encrypted log group."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days to retain the job log group (/aws/batch/<Environment>-<name>)"
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}
