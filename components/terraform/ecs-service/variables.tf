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
  description = "Short name. The service, task definition family and target group are named <Environment>-<name>, the log group /ecs/<Environment>-<name>, the roles <Environment>-<name>-task-execution and <Environment>-<name>-task"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,38}[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 1-40 characters of letters, digits or hyphen, not starting or ending with a hyphen (it ends the target group name, which takes no underscore and no trailing hyphen)."
  }
}

# Cloud Posse aws-ecs-service / ecs-alb-service-task names below where they
# fit (ecs_cluster_arn, launch_type, task_cpu, task_memory, desired_count,
# deployment_*_percent, circuit_breaker_*, exec_enabled, propagate_tags,
# wait_for_steady_state, capacity_provider_strategies, task_exec_role_arn,
# task_role_arn, task_policy_arns, runtime_platform, ephemeral_storage_size,
# health_check_grace_period_seconds, containers, autoscaling_enabled-style
# min/max capacity). The network mode is always awsvpc.

variable "ecs_cluster_arn" {
  type        = string
  description = "ARN of the ECS cluster the service runs in (an ecs instance's .cluster_arn)"
  default     = null

  validation {
    condition     = var.ecs_cluster_arn == null || can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]{1,255}$", var.ecs_cluster_arn))
    error_message = "ecs_cluster_arn must be an ECS cluster ARN (arn:aws:ecs:<region>:<account>:cluster/<name>)."
  }

  validation {
    condition     = var.ecs_cluster_arn != null || !var.enabled
    error_message = "ecs_cluster_arn is required (an ecs instance's .cluster_arn)."
  }
}

variable "launch_type" {
  type        = string
  description = "FARGATE (default) or EC2: the task definition's compatibility, and the service's launch type unless capacity_provider_strategies is set"
  default     = "FARGATE"
  nullable    = false

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "launch_type must be FARGATE or EC2."
  }
}

variable "platform_version" {
  type        = string
  description = "Fargate platform version (FARGATE only)"
  default     = "LATEST"
  nullable    = false

  validation {
    condition     = can(regex("^(LATEST|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.platform_version))
    error_message = "platform_version must be LATEST or a version like 1.4.0."
  }
}

variable "capacity_provider_strategies" {
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  description = "Capacity provider strategy, replacing launch_type on the service: FARGATE/FARGATE_SPOT for launch_type FARGATE, the cluster's EC2 (Auto Scaling group) capacity providers for EC2. Empty uses launch_type"
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for s in var.capacity_provider_strategies : try(s.weight >= 0 && s.weight <= 1000 && s.base >= 0 && s.base <= 100000, false)
    ])
    error_message = "capacity_provider_strategies weight must be 0-1000 and base 0-100000."
  }

  validation {
    condition     = length(distinct([for s in var.capacity_provider_strategies : s.capacity_provider])) == length(var.capacity_provider_strategies)
    error_message = "capacity_provider_strategies entries need distinct capacity providers."
  }

  validation {
    condition     = length([for s in var.capacity_provider_strategies : s if s.base > 0]) <= 1
    error_message = "Only one capacity_provider_strategies entry may set base."
  }

  validation {
    condition = alltrue([
      for s in var.capacity_provider_strategies :
      contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider) == (var.launch_type == "FARGATE")
    ])
    error_message = "capacity_provider_strategies must use FARGATE/FARGATE_SPOT with launch_type FARGATE, and only EC2 (Auto Scaling group) capacity providers with launch_type EC2."
  }
}

# Fargate's documented task cpu (units) / memory (MiB) combinations.
variable "task_cpu" {
  type        = number
  description = "Task CPU units (256 = 0.25 vCPU). Required for FARGATE (a documented cpu/memory pair); optional for EC2"
  default     = null

  validation {
    condition     = var.launch_type != "FARGATE" || contains([256, 512, 1024, 2048, 4096, 8192, 16384], coalesce(var.task_cpu, 0))
    error_message = "A FARGATE task needs task_cpu 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }

  validation {
    condition     = var.task_cpu == null || try(var.task_cpu >= 128 && floor(var.task_cpu) == var.task_cpu, false)
    error_message = "task_cpu must be a whole number of CPU units, at least 128."
  }
}

variable "task_memory" {
  type        = number
  description = "Task memory (MiB). Required for FARGATE, paired with task_cpu: 256 with 512, 1024 or 2048; 512 with 1024-4096; 1024 with 2048-8192; 2048 with 4096-16384; 4096 with 8192-30720 (1024 steps); 8192 with 16384-61440 (4096 steps); 16384 with 32768-122880 (8192 steps). Optional for EC2 (then every container needs memory or memory_reservation)"
  default     = null

  validation {
    condition = var.launch_type != "FARGATE" || contains(lookup({
      "256"   = [512, 1024, 2048]
      "512"   = range(1024, 4097, 1024)
      "1024"  = range(2048, 8193, 1024)
      "2048"  = range(4096, 16385, 1024)
      "4096"  = range(8192, 30721, 1024)
      "8192"  = range(16384, 61441, 4096)
      "16384" = range(32768, 122881, 8192)
    }, tostring(coalesce(var.task_cpu, 0)), []), coalesce(var.task_memory, 0))
    error_message = "A FARGATE task needs a supported task_cpu/task_memory (MiB) pair: 256 with 512, 1024 or 2048; 512 with 1024-4096; 1024 with 2048-8192; 2048 with 4096-16384; 4096 with 8192-30720 (1024 steps); 8192 with 16384-61440 (4096 steps); 16384 with 32768-122880 (8192 steps)."
  }

  validation {
    condition     = var.task_memory == null || try(var.task_memory >= 6 && floor(var.task_memory) == var.task_memory, false)
    error_message = "task_memory must be a whole number of MiB, at least 6."
  }
}

variable "runtime_platform" {
  type = object({
    cpu_architecture        = optional(string, "X86_64")
    operating_system_family = optional(string, "LINUX")
  })
  description = "Task runtime platform: cpu_architecture X86_64 (default) or ARM64, operating_system_family LINUX. Null leaves it unset (X86_64 Linux)"
  default     = null

  validation {
    condition     = var.runtime_platform == null || contains(["X86_64", "ARM64"], try(var.runtime_platform.cpu_architecture, ""))
    error_message = "runtime_platform.cpu_architecture must be X86_64 or ARM64."
  }

  validation {
    condition     = var.runtime_platform == null || try(var.runtime_platform.operating_system_family, "") == "LINUX"
    error_message = "runtime_platform.operating_system_family must be LINUX (the containers' awslogs and linux_parameters assume Linux)."
  }
}

variable "ephemeral_storage_size" {
  type        = number
  description = "Fargate ephemeral storage (GiB, 21-200); null is Fargate's 20 GiB. FARGATE only"
  default     = null

  validation {
    condition     = var.ephemeral_storage_size == null || try(var.ephemeral_storage_size >= 21 && var.ephemeral_storage_size <= 200 && floor(var.ephemeral_storage_size) == var.ephemeral_storage_size, false)
    error_message = "ephemeral_storage_size must be a whole number between 21 and 200 (unset is Fargate's 20 GiB)."
  }

  validation {
    condition     = var.ephemeral_storage_size == null || var.launch_type == "FARGATE"
    error_message = "ephemeral_storage_size applies to FARGATE tasks only."
  }
}

# The Cloud Posse aws-ecs-service containers map, keyed by container name, with
# snake_case attributes (the ecs-container-definition module's inputs) instead
# of raw container definition JSON, so the roles, log group and load balancer
# checks can be derived from it.
variable "containers" {
  type = map(object({
    image = string
    # Container-level CPU units and memory (hard limit) / memory_reservation
    # (soft limit), MiB. Optional on FARGATE (the task size applies).
    cpu                = optional(number)
    memory             = optional(number)
    memory_reservation = optional(number)
    essential          = optional(bool, true)

    # awsvpc: host_port is omitted or equal to container_port.
    port_mappings = optional(list(object({
      container_port = number
      host_port      = optional(number)
      protocol       = optional(string, "tcp")
      name           = optional(string)
      app_protocol   = optional(string)
    })), [])

    environment = optional(map(string), {})
    # Environment variable name -> Secrets Manager secret ARN (the full ARN with
    # its 6-character suffix, optionally :json-key:version-stage:version-id) or
    # SSM parameter ARN. The created execution role is granted exactly these.
    secrets = optional(map(string), {})

    command           = optional(list(string), [])
    entrypoint        = optional(list(string), [])
    working_directory = optional(string)
    user              = optional(string)
    stop_timeout      = optional(number)

    # A container that writes to local disk (/tmp included) needs false: the
    # component mounts no volumes.
    readonly_root_filesystem = optional(bool, true)

    healthcheck = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number)
    }))

    linux_parameters = optional(object({
      init_process_enabled = optional(bool, false)
    }))

    # awslogs to the component's /ecs/<Environment>-<name> log group; the stream
    # prefix defaults to the container name.
    log_stream_prefix = optional(string)
  }))
  description = "Container definitions by container name: image, cpu, memory, memory_reservation, essential (default true), port_mappings (container_port, host_port, protocol, name, app_protocol), environment, secrets (env name -> Secrets Manager secret ARN with its 6-character suffix, or SSM parameter ARN), command, entrypoint, working_directory, user, stop_timeout, readonly_root_filesystem (default true), healthcheck, linux_parameters.init_process_enabled and log_stream_prefix. Every container logs with awslogs to the component log group"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.containers) : can(regex("^[a-zA-Z0-9_-]{1,255}$", k))])
    error_message = "containers keys (container names) must be 1-255 characters of letters, digits, underscore or hyphen."
  }

  validation {
    condition     = length(var.containers) > 0 || !var.enabled
    error_message = "containers needs at least one container."
  }

  validation {
    condition     = length(var.containers) == 0 || anytrue([for c in values(var.containers) : c.essential])
    error_message = "At least one container must be essential."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : try(trimspace(c.image) != "", false)])
    error_message = "Every container needs a non-empty image."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) : alltrue([
        c.cpu == null || try(c.cpu >= 0 && floor(c.cpu) == c.cpu, false),
        c.memory == null || try(c.memory >= 6 && floor(c.memory) == c.memory, false),
        c.memory_reservation == null || try(c.memory_reservation >= 6 && floor(c.memory_reservation) == c.memory_reservation, false),
        c.memory == null || c.memory_reservation == null || try(c.memory_reservation <= c.memory, false),
      ])
    ])
    error_message = "Container cpu must be whole CPU units >= 0; memory and memory_reservation whole MiB >= 6, with memory_reservation <= memory."
  }

  validation {
    condition = var.task_memory != null || alltrue([
      for c in values(var.containers) : c.memory != null || c.memory_reservation != null
    ])
    error_message = "Without task_memory every container needs memory or memory_reservation."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [
        for p in c.port_mappings : alltrue([
          try(p.container_port >= 1 && p.container_port <= 65535 && floor(p.container_port) == p.container_port, false),
          p.host_port == null || try(p.host_port == p.container_port, false),
          contains(["tcp", "udp"], coalesce(p.protocol, "tcp")),
          p.app_protocol == null || contains(["http", "http2", "grpc"], coalesce(p.app_protocol, "-")),
        ])
      ]
    ]))
    error_message = "port_mappings need container_port 1-65535, host_port unset or equal to container_port (awsvpc), protocol tcp or udp, app_protocol http, http2 or grpc."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) : length(distinct([for p in c.port_mappings : "${p.container_port}/${coalesce(p.protocol, "tcp")}"])) == length(c.port_mappings)
    ])
    error_message = "A container's port_mappings need distinct container_port/protocol pairs."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [for n in concat(keys(c.environment), keys(c.secrets)) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", n))]
    ]))
    error_message = "environment and secrets keys must be environment variable names (letters, digits, underscore; not starting with a digit)."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) : length(setintersection(keys(c.environment), keys(c.secrets))) == 0
    ])
    error_message = "A variable cannot be in both a container's environment and its secrets."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [
        for arn in values(c.secrets) :
        can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:[^:]+-[A-Za-z0-9]{6}(:[^:]*:[^:]*:[^:]*)?$", arn)) ||
        can(regex("^arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{12}:parameter/.+$", arn))
      ]
    ]))
    error_message = "secrets maps an environment variable name to a full Secrets Manager secret ARN (arn:aws:secretsmanager:<region>:<account>:secret:<name>-<6-character suffix>, optionally :<json-key>:<version-stage>:<version-id>) or an SSM parameter ARN (arn:aws:ssm:<region>:<account>:parameter/<name>). Names and suffix-less ARNs are rejected: the execution role is scoped to the exact ARNs."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) : c.healthcheck == null || try(
        length(c.healthcheck.command) > 0 && contains(["CMD", "CMD-SHELL", "NONE"], c.healthcheck.command[0])
        && c.healthcheck.interval >= 5 && c.healthcheck.interval <= 300
        && c.healthcheck.timeout >= 2 && c.healthcheck.timeout <= 60
        && c.healthcheck.retries >= 1 && c.healthcheck.retries <= 10
        && (c.healthcheck.start_period == null || (c.healthcheck.start_period >= 0 && c.healthcheck.start_period <= 300)),
        false
      )
    ])
    error_message = "healthcheck needs a command starting with CMD, CMD-SHELL or NONE, interval 5-300, timeout 2-60, retries 1-10 and start_period 0-300 seconds."
  }

  validation {
    condition     = alltrue([for c in values(var.containers) : c.stop_timeout == null || try(c.stop_timeout >= 0 && c.stop_timeout <= 120, false)])
    error_message = "stop_timeout must be 0-120 seconds."
  }
}

# Service.
variable "desired_count" {
  type        = number
  description = "Number of tasks to run. Ignored after creation when autoscaling is set (Application Auto Scaling owns it)"
  default     = 1
  nullable    = false

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a whole number >= 0."
  }
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  description = "Lower bound (percent of desired_count) of running tasks during a rolling deployment"
  default     = 100
  nullable    = false

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "deployment_minimum_healthy_percent must be between 0 and 100."
  }
}

variable "deployment_maximum_percent" {
  type        = number
  description = "Upper bound (percent of desired_count) of running tasks during a rolling deployment"
  default     = 200
  nullable    = false

  validation {
    condition     = var.deployment_maximum_percent >= 100 && var.deployment_maximum_percent <= 200
    error_message = "deployment_maximum_percent must be between 100 and 200."
  }
}

variable "circuit_breaker_deployment_enabled" {
  type        = bool
  description = "Enable the deployment circuit breaker (fails a deployment whose tasks do not reach steady state)"
  default     = true
  nullable    = false
}

variable "circuit_breaker_rollback_enabled" {
  type        = bool
  description = "Roll back to the last completed deployment when the circuit breaker fails one"
  default     = true
  nullable    = false
}

variable "wait_for_steady_state" {
  type        = bool
  description = "Make apply wait for the service to reach steady state"
  default     = false
  nullable    = false
}

variable "propagate_tags" {
  type        = string
  description = "Copy tags to the tasks from SERVICE (default), TASK_DEFINITION or NONE"
  default     = "SERVICE"
  nullable    = false

  validation {
    condition     = contains(["SERVICE", "TASK_DEFINITION", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be SERVICE, TASK_DEFINITION or NONE."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the tasks' ENIs (awsvpc), usually vpc/main .private_subnet_ids"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]+$", s))])
    error_message = "subnet_ids entries must be subnet ids (subnet-...)."
  }

  validation {
    condition     = length(var.subnet_ids) > 0 || !var.enabled
    error_message = "subnet_ids needs at least one subnet."
  }

  validation {
    condition     = length(var.subnet_ids) <= 16
    error_message = "A service takes at most 16 subnet_ids."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups for the tasks' ENIs (a securitygroup instance's ids). The component creates none"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", s))])
    error_message = "security_group_ids entries must be security group ids (sg-...)."
  }

  validation {
    condition     = (length(var.security_group_ids) > 0 && length(var.security_group_ids) <= 5) || !var.enabled
    error_message = "security_group_ids needs 1 to 5 security groups."
  }
}

variable "assign_public_ip" {
  type        = bool
  description = "Give the tasks public IPs (FARGATE only; only for public subnets without a NAT gateway). Default false: private subnets need a NAT gateway or VPC endpoints (ECR, S3, Logs, Secrets Manager/SSM)"
  default     = false
  nullable    = false

  validation {
    condition     = !var.assign_public_ip || var.launch_type == "FARGATE"
    error_message = "assign_public_ip applies to FARGATE tasks only."
  }
}

variable "exec_enabled" {
  type        = bool
  description = "Enable ECS Exec (enable_execute_command). The created task role gets the ssmmessages permissions it needs (and kms:Decrypt on exec_kms_key_arn); a task_role_arn must grant them itself. Needs readonly_root_filesystem = false on every container"
  default     = false
  nullable    = false

  # AWS ECS Exec considerations: a read-only root filesystem is not supported
  # (the SSM agent writes into the container).
  validation {
    condition     = var.exec_enabled == false || alltrue([for c in values(var.containers) : c.readonly_root_filesystem == false])
    error_message = "exec_enabled needs readonly_root_filesystem = false on every container: ECS Exec does not support a read-only root filesystem."
  }
}

variable "exec_kms_key_arn" {
  type        = string
  description = "KMS key the cluster's execute_command_configuration encrypts ECS Exec sessions with; the created task role gets kms:Decrypt on it. Null when the cluster sets none"
  default     = null

  validation {
    condition     = var.exec_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.exec_kms_key_arn))
    error_message = "exec_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

# Roles (Cloud Posse ecs-alb-service-task pattern: created unless an ARN is given).
variable "task_exec_role_arn" {
  type        = string
  description = "Existing task execution role. Null creates <Environment>-<name>-task-execution, scoped to the component log group, ecr_repository_arns, the containers' secrets and secrets_kms_key_arn"
  default     = null

  validation {
    condition     = var.task_exec_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.task_exec_role_arn))
    error_message = "task_exec_role_arn must be an IAM role ARN."
  }
}

variable "task_role_arn" {
  type        = string
  description = "Existing task role (the containers' AWS credentials). Null creates <Environment>-<name>-task when task_policy_arns, task_policy_json or exec_enabled is set; otherwise the tasks run without AWS credentials"
  default     = null

  validation {
    condition     = var.task_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.task_role_arn))
    error_message = "task_role_arn must be an IAM role ARN."
  }
}

variable "task_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs attached to the created task role"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.task_policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "task_policy_arns entries must be IAM policy ARNs."
  }

  validation {
    condition     = var.task_role_arn == null || length(var.task_policy_arns) == 0
    error_message = "task_role_arn uses an existing role: leave task_policy_arns unset with it."
  }
}

variable "task_policy_json" {
  type        = string
  description = "Inline IAM policy document for the created task role"
  default     = null

  validation {
    condition     = var.task_policy_json == null || can(jsondecode(var.task_policy_json).Statement)
    error_message = "task_policy_json must be an IAM policy document (JSON with a Statement)."
  }

  validation {
    condition     = var.task_role_arn == null || var.task_policy_json == null
    error_message = "task_role_arn uses an existing role: leave task_policy_json unset with it."
  }
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "ECR repositories the created execution role may pull from. Empty allows every repository (\"*\"), as AmazonECSTaskExecutionRolePolicy does"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", a))])
    error_message = "ecr_repository_arns entries must be ECR repository ARNs (arn:aws:ecr:<region>:<account>:repository/<name>)."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Customer managed KMS key encrypting the containers' secrets (Secrets Manager secrets, SecureString parameters). The created execution role gets kms:Decrypt on it through Secrets Manager and SSM only. Null for AWS managed keys"
  default     = null

  validation {
    condition     = var.secrets_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.secrets_kms_key_arn))
    error_message = "secrets_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "log_kms_key_arn" {
  type        = string
  description = "KMS key ARN (the stack's kms/main .key_arn) encrypting the log group /ecs/<Environment>-<name>; its policy must allow logs.<region>.amazonaws.com (kms allow_cloudwatch_logs)"
  default     = null

  validation {
    condition     = var.log_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }

  validation {
    condition     = var.log_kms_key_arn != null || !var.enabled
    error_message = "log_kms_key_arn (kms/main .key_arn) is required for the encrypted log group."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days to retain the log group (/ecs/<Environment>-<name>)"
  default     = 90
  nullable    = false

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

# Load balancer: one target group (<Environment>-<name>) and one listener rule
# on an existing listener (an alb instance's .https_listener_arn).
variable "load_balancer" {
  type = object({
    listener_arn   = string
    vpc_id         = string
    container_name = string
    container_port = number
    priority       = number
    # At least one condition; values are ORed within a list, the lists ANDed.
    host_headers  = optional(list(string), [])
    path_patterns = optional(list(string), [])
    # A header the request must also carry, its value read at plan from an SSM
    # parameter (SecureString), never written in a stack: CloudFront's secret
    # origin-verify header, with the alb instance's default action a fixed 403.
    # Cloud Posse's alb-ingress takes literal listener_http_header_conditions;
    # this one reads its single value from SSM instead.
    http_header = optional(object({
      name                     = string
      value_ssm_parameter_name = string
    }))

    protocol             = optional(string, "HTTP")
    deregistration_delay = optional(number, 300)
    health_check = optional(object({
      path                = optional(string, "/")
      matcher             = optional(string, "200-399")
      port                = optional(string, "traffic-port")
      protocol            = optional(string, "HTTP")
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
      timeout             = optional(number, 5)
      interval            = optional(number, 30)
    }), {})
  })
  description = "Optional ALB attachment: a target group (<Environment>-<name>, ip targets) forwarded to by a listener rule on listener_arn (priority, host_headers and/or path_patterns, and optionally http_header: a header name whose required value is read from the SSM parameter value_ssm_parameter_name), registering container_name:container_port (a port_mappings entry of that container). vpc_id is the target group's VPC; protocol, deregistration_delay and health_check configure the target group. Null attaches no load balancer"
  default     = null

  validation {
    condition     = var.load_balancer == null || can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:listener/app/[^/]+/[0-9a-f]+/[0-9a-f]+$", var.load_balancer.listener_arn))
    error_message = "load_balancer.listener_arn must be an Application Load Balancer listener ARN (...:listener/app/<name>/<id>/<id>)."
  }

  validation {
    condition     = var.load_balancer == null || can(regex("^vpc-[0-9a-f]+$", var.load_balancer.vpc_id))
    error_message = "load_balancer.vpc_id must be a VPC id (vpc-...)."
  }

  validation {
    condition = var.load_balancer == null || try(
      contains([for p in var.containers[var.load_balancer.container_name].port_mappings : p.container_port if coalesce(p.protocol, "tcp") == "tcp"], var.load_balancer.container_port),
      false
    )
    error_message = "load_balancer.container_name must be a containers key, and container_port a tcp port_mappings container_port of that container."
  }

  validation {
    condition     = var.load_balancer == null || try(var.load_balancer.priority >= 1 && var.load_balancer.priority <= 50000 && floor(var.load_balancer.priority) == var.load_balancer.priority, false)
    error_message = "load_balancer.priority must be a whole number between 1 and 50000."
  }

  validation {
    condition = var.load_balancer == null || try(
      length(var.load_balancer.host_headers) + length(var.load_balancer.path_patterns) > 0
      && length(var.load_balancer.host_headers) + length(var.load_balancer.path_patterns) + (var.load_balancer.http_header == null ? 0 : 1) <= 5,
      false
    )
    error_message = "load_balancer needs 1 to 5 host_headers and path_patterns values, http_header counting as one more (a listener rule takes at most 5 condition values)."
  }

  validation {
    condition = try(var.load_balancer.http_header, null) == null || try(
      can(regex("^[A-Za-z0-9-]{1,40}$", var.load_balancer.http_header.name))
      && !contains(["host", "cookie"], lower(var.load_balancer.http_header.name))
      && can(regex("^/?[A-Za-z0-9_./-]+$", var.load_balancer.http_header.value_ssm_parameter_name))
      && length(var.load_balancer.http_header.value_ssm_parameter_name) <= 2048,
      false
    )
    error_message = "load_balancer.http_header needs a name of 1-40 letters, digits or hyphens (not Host or Cookie, which have their own conditions) and value_ssm_parameter_name, an SSM parameter name (e.g. /app/origin-verify), not an ARN."
  }

  validation {
    condition = var.load_balancer == null || try(
      contains(["HTTP", "HTTPS"], var.load_balancer.protocol) && contains(["HTTP", "HTTPS"], var.load_balancer.health_check.protocol),
      false
    )
    error_message = "load_balancer protocol and health_check.protocol must be HTTP or HTTPS."
  }

  validation {
    condition     = var.load_balancer == null || try(var.load_balancer.deregistration_delay >= 0 && var.load_balancer.deregistration_delay <= 3600, false)
    error_message = "load_balancer.deregistration_delay must be 0-3600 seconds."
  }

  validation {
    condition = var.load_balancer == null || try(
      var.load_balancer.health_check.healthy_threshold >= 2 && var.load_balancer.health_check.healthy_threshold <= 10
      && var.load_balancer.health_check.unhealthy_threshold >= 2 && var.load_balancer.health_check.unhealthy_threshold <= 10
      && var.load_balancer.health_check.interval >= 5 && var.load_balancer.health_check.interval <= 300
      && var.load_balancer.health_check.timeout >= 2 && var.load_balancer.health_check.timeout <= 120
      && var.load_balancer.health_check.timeout < var.load_balancer.health_check.interval
      && startswith(var.load_balancer.health_check.path, "/"),
      false
    )
    error_message = "load_balancer.health_check needs a path starting with /, healthy/unhealthy thresholds 2-10, interval 5-300 and timeout 2-120 seconds (timeout below interval)."
  }
}

variable "health_check_grace_period_seconds" {
  type        = number
  description = "Seconds the service ignores failing load balancer health checks after a task starts (only with load_balancer)"
  default     = 60
  nullable    = false

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "health_check_grace_period_seconds must be >= 0."
  }
}

# Target-tracking autoscaling of the service's desired count.
variable "autoscaling" {
  type = object({
    min_capacity = number
    max_capacity = number
    # Target values; set at least one. Utilization targets are percentages;
    # alb_request_count_per_target needs load_balancer.
    cpu_utilization_target       = optional(number)
    memory_utilization_target    = optional(number)
    alb_request_count_per_target = optional(number)
    scale_in_cooldown            = optional(number, 300)
    scale_out_cooldown           = optional(number, 60)
  })
  description = "Optional target-tracking autoscaling: min_capacity, max_capacity and one or more of cpu_utilization_target, memory_utilization_target (percent) and alb_request_count_per_target (needs load_balancer), with scale_in_cooldown/scale_out_cooldown seconds. desired_count is then ignored after creation. Null disables autoscaling"
  default     = null

  validation {
    condition = var.autoscaling == null || try(
      var.autoscaling.min_capacity >= 0 && var.autoscaling.min_capacity <= var.autoscaling.max_capacity
      && floor(var.autoscaling.min_capacity) == var.autoscaling.min_capacity && floor(var.autoscaling.max_capacity) == var.autoscaling.max_capacity,
      false
    )
    error_message = "autoscaling needs whole min_capacity and max_capacity with 0 <= min_capacity <= max_capacity."
  }

  validation {
    condition = var.autoscaling == null || try(anytrue([
      var.autoscaling.cpu_utilization_target != null,
      var.autoscaling.memory_utilization_target != null,
      var.autoscaling.alb_request_count_per_target != null,
    ]), false)
    error_message = "autoscaling needs at least one of cpu_utilization_target, memory_utilization_target or alb_request_count_per_target."
  }

  validation {
    condition = var.autoscaling == null || try(alltrue([
      var.autoscaling.cpu_utilization_target == null || (var.autoscaling.cpu_utilization_target > 0 && var.autoscaling.cpu_utilization_target <= 100),
      var.autoscaling.memory_utilization_target == null || (var.autoscaling.memory_utilization_target > 0 && var.autoscaling.memory_utilization_target <= 100),
      var.autoscaling.alb_request_count_per_target == null || var.autoscaling.alb_request_count_per_target > 0,
      var.autoscaling.scale_in_cooldown >= 0, var.autoscaling.scale_out_cooldown >= 0,
    ]), false)
    error_message = "autoscaling utilization targets must be in (0, 100], alb_request_count_per_target above 0 and cooldowns >= 0."
  }

  validation {
    condition     = try(var.autoscaling.alb_request_count_per_target, null) == null || var.load_balancer != null
    error_message = "autoscaling.alb_request_count_per_target needs load_balancer (it tracks the service's target group)."
  }
}
