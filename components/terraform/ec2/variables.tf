# One instance per component instance, as in
# cloudposse-terraform-components/aws-ec2-instance. Variable names follow
# cloudposse/terraform-aws-ec2-instance where it has the setting; the rest keep
# this repo's names.

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
# must not repeat the Environment: prod sets `bastion`, not `production-bastion`.
variable "name" {
  type        = string
  description = "Instance name without the Environment prefix. The instance is named <tags.Environment>-<name>."

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]*$", var.name))
    error_message = "name may only contain letters, digits, '-' and '_'."
  }

  validation {
    condition = (
      lower(var.name) != lower(lookup(var.tags, "Environment", "")) &&
      !startswith(lower(var.name), "${lower(lookup(var.tags, "Environment", ""))}-")
    )
    error_message = "name must not start with tags.Environment: the component already prefixes it, and repeating it doubles the Environment in every name."
  }

  # The longest IAM name built from the prefix is the role
  # "<Environment>-<name>-role"; IAM allows 64 characters.
  validation {
    condition     = length("${lookup(var.tags, "Environment", "")}-${var.name}-role") <= 64
    error_message = "<tags.Environment>-<name>-role must fit IAM's 64-character role name limit: shorten name."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the instance and its security group are created"

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (e.g., vpc-0123abcd)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Candidate subnet IDs; the first is used when `subnet` is not set"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[a-z0-9]+$", id))])
    error_message = "All subnet IDs must be in a valid format (e.g., subnet-abc123)."
  }
}

variable "subnet" {
  type        = string
  description = "Subnet ID to launch the instance in. null: the first of subnet_ids."
  default     = null

  validation {
    condition     = var.subnet == null || can(regex("^subnet-[a-z0-9]+$", var.subnet))
    error_message = "subnet must be a subnet ID (e.g., subnet-abc123)."
  }
}

variable "instance_type" {
  type        = string
  description = "The type of the instance (e.g., t3.small)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like <family>.<size>, e.g. t3.small."
  }
}

variable "ami" {
  type        = string
  description = "AMI ID. Empty resolves the latest Amazon Linux 2023 image."
  default     = ""
  nullable    = false

  validation {
    condition     = var.ami == "" || can(regex("^ami-[a-f0-9]+$", var.ami))
    error_message = "ami must be empty or an AMI ID (e.g., ami-0123abcd)."
  }
}

variable "ssh_key_pair" {
  type        = string
  description = "Name of an existing key pair to launch with. null or empty: generate one when create_ssh_keys is true, otherwise launch without a key (SSM access only)."
  default     = null
}

variable "associate_public_ip_address" {
  type        = bool
  description = "Associate a public IP address with the instance"
  default     = false
}

variable "user_data" {
  type        = string
  description = "User data, as plain text (the component base64-encodes it where AWS needs that)"
  default     = null
}

variable "monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring"
  default     = true
}

variable "ebs_optimized" {
  type        = bool
  description = "Launch an EBS-optimized instance"
  default     = true
}

variable "disable_api_termination" {
  type        = bool
  description = "Enable EC2 termination protection"
  default     = false

  validation {
    condition     = var.environment != "prod" || var.disable_api_termination
    error_message = "API termination protection must be enabled for production environments."
  }
}

# Divergence from Cloud Posse (gp2, 10 GB): gp3 is cheaper and faster, and 20
# GB leaves room above the Amazon Linux 2023 image.
variable "root_volume_type" {
  type        = string
  description = "Root volume type"
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1", "standard"], var.root_volume_type)
    error_message = "root_volume_type must be an EBS volume type."
  }
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GiB"
  default     = 20

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}

variable "delete_on_termination" {
  type        = bool
  description = "Delete the root volume when the instance terminates"
  default     = true
}

variable "root_block_device_encrypted" {
  type        = bool
  description = "Encrypt the root volume"
  default     = true
}

variable "root_block_device_kms_key_id" {
  type        = string
  description = "KMS key ARN for the root and additional volumes. null: the AWS-managed EBS key."
  default     = null
}

variable "ebs_block_devices" {
  type = list(object({
    device_name           = string
    volume_type           = optional(string, "gp3")
    volume_size           = number
    iops                  = optional(number)
    throughput            = optional(number)
    delete_on_termination = optional(bool, true)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string)
    snapshot_id           = optional(string)
  }))
  description = "Additional EBS volumes. kms_key_id falls back to root_block_device_kms_key_id."
  default     = []
  nullable    = false
}

# The instance's own security group, with inline rules. Cloud Posse builds
# the group from `security_group_rules` instead; README.md ("Security group")
# says why this keeps inline rules. Only inbound traffic is restricted:
# ingress may not be open to everywhere, egress is unrestricted by policy.
variable "allowed_ingress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    description     = optional(string)
  }))
  description = "Ingress rules of the instance's own security group"
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for r in var.allowed_ingress_rules : alltrue([
      for c in(r.cidr_blocks == null ? [] : r.cidr_blocks) : try(split("/", c)[1] != "0", true)
    ])])
    error_message = "Ingress must not be open to everywhere (0.0.0.0/0 or any other /0)."
  }
}

variable "allowed_egress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    description     = optional(string)
  }))
  description = "Egress rules of the instance's own security group. null: all outbound traffic (Cloud Posse's default; egress is unrestricted by policy)."
  default     = null
}

variable "security_groups" {
  type        = list(string)
  description = "Additional security group IDs to attach besides the instance's own"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for sg in var.security_groups : can(regex("^sg-[a-z0-9]+$", sg))])
    error_message = "All security group IDs must be in a valid format (e.g., sg-abc123)."
  }
}

variable "enable_ssm" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore to the instance role"
  default     = true
}

variable "custom_iam_policy" {
  type        = string
  description = "JSON of an extra inline policy for the instance role. Empty: none."
  default     = ""
  nullable    = false

  validation {
    condition     = var.custom_iam_policy == "" || can(jsondecode(var.custom_iam_policy))
    error_message = "custom_iam_policy must be empty or a JSON policy document."
  }
}

# SSH key generation, used only when ssh_key_pair is not set.
variable "create_ssh_keys" {
  type        = bool
  description = "Generate a key pair for the instance when ssh_key_pair is not set"
  default     = false
}

variable "store_ssh_keys_in_secrets_manager" {
  type        = bool
  description = "Store a generated private key in Secrets Manager"
  default     = true
}

# ED25519: shorter keys, faster, and accepted by EC2 for Linux instances.
# RSA stays available for Windows, which EC2 key pairs require it for.
variable "ssh_key_algorithm" {
  type        = string
  description = "Algorithm of a generated key: ED25519 (default) or RSA"
  default     = "ED25519"

  validation {
    condition     = contains(["RSA", "ED25519"], var.ssh_key_algorithm)
    error_message = "Only RSA and ED25519 are supported for SSH key generation."
  }
}

variable "ssh_key_secret_kms_key_id" {
  type        = string
  description = "KMS key (ARN, key ID or alias) encrypting the Secrets Manager secret that holds a generated private key. null: the AWS-managed aws/secretsmanager key."
  default     = null

  validation {
    condition = var.ssh_key_secret_kms_key_id == null ? true : can(regex(
      "^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|mrk-[0-9a-f]{32}|alias/.+)$",
      var.ssh_key_secret_kms_key_id
    ))
    error_message = "ssh_key_secret_kms_key_id must be a KMS key ARN, alias ARN, key ID, multi-Region key ID or alias/<name>."
  }
}

variable "ssh_key_secret_recovery_window_in_days" {
  type        = number
  description = "Days a deleted private-key secret stays recoverable: 0 (delete at once) or 7-30, as Cloud Posse's secrets-manager recovery_window_in_days"
  default     = 30

  validation {
    condition     = var.ssh_key_secret_recovery_window_in_days == 0 || (var.ssh_key_secret_recovery_window_in_days >= 7 && var.ssh_key_secret_recovery_window_in_days <= 30)
    error_message = "ssh_key_secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "ssh_key_rsa_bits" {
  type        = number
  description = "Size of a generated RSA key in bits"
  default     = 4096

  validation {
    condition     = var.ssh_key_rsa_bits >= 2048 && var.ssh_key_rsa_bits <= 8192
    error_message = "ssh_key_rsa_bits must be between 2048 and 8192."
  }
}

# Instance metadata (IMDS), Cloud Posse names, applied to the instance and the
# launch template alike.
variable "metadata_http_tokens_required" {
  type        = bool
  description = "Require IMDSv2 session tokens"
  default     = true
}

# Divergence from Cloud Posse (2): 1 keeps IMDS on the instance itself.
variable "metadata_http_put_response_hop_limit" {
  type        = number
  description = "IMDS PUT response hop limit"
  default     = 1

  validation {
    condition     = var.metadata_http_put_response_hop_limit >= 1 && var.metadata_http_put_response_hop_limit <= 64
    error_message = "metadata_http_put_response_hop_limit must be between 1 and 64."
  }
}

variable "metadata_tags_enabled" {
  type        = bool
  description = "Expose the instance tags through IMDS"
  default     = false
}

# Launch template. Cloud Posse's ec2-instance has none, hence off by default.
variable "enable_launch_templates" {
  type        = bool
  description = "Create a launch template for the instance"
  default     = false
}

variable "create_instances_from_templates" {
  type        = bool
  description = "Launch the instance from the launch template instead of standalone. Requires enable_launch_templates."
  default     = false

  validation {
    condition     = !var.create_instances_from_templates || var.enable_launch_templates
    error_message = "create_instances_from_templates requires enable_launch_templates = true."
  }
}

variable "enable_network_interface_config" {
  type        = bool
  description = "Configure the network interface (subnet, security groups) in the launch template rather than on the instance"
  default     = true
}

variable "enable_resource_name_dns" {
  type        = bool
  description = "Launch template: resource-name based private DNS (hostname_type = ip-name, A record)"
  default     = true
}

variable "environment" {
  type        = string
  description = "Lifecycle tier (dev, staging, prod) for validation rules; not part of any name"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
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
