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
  description = "Short name. The load balancer, its default target group and its security group are named <Environment>-<name>"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 1-20 characters of lowercase letters, digits or hyphens (kept short: it is combined with Environment and a suffix under the 32-character ALB/target-group name limit)."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id the load balancer and its security group are created in"
}

variable "subnets" {
  type        = list(string)
  description = "Subnet ids for the load balancer (public subnets for an internet-facing ALB)"

  validation {
    condition     = length(var.subnets) > 0
    error_message = "At least one subnet is required."
  }
}

variable "internal" {
  type        = bool
  description = "Whether the load balancer is internal (no public IP) rather than internet-facing"
  default     = false
}

# ---------------------------------------------------------------------------
# Inbound access. The Cloud Posse aws-alb component leaves ALB ingress to the
# caller's security groups; this component instead owns its own security
# group and resolves the CloudFront origin-facing managed prefix list itself,
# so no stack can accidentally open the ALB to 0.0.0.0/0. Additional sources
# are prefix lists or security group ids only -- never a CIDR block.
# ---------------------------------------------------------------------------

variable "additional_ingress_prefix_list_ids" {
  type        = list(string)
  description = "Extra managed prefix list ids allowed to reach the HTTPS listener, alongside the CloudFront origin-facing prefix list this component always resolves. Quota note: a security group rule referencing a managed prefix list counts against the 'Rules per security group' quota as that list's max-entries weight, not as 1 -- the CloudFront origin-facing list alone is already ~55-60 of the default 60, so adding an entry here can require an AWS quota increase for that security group."
  default     = []
  nullable    = false
}

variable "additional_ingress_security_group_ids" {
  type        = list(string)
  description = "Extra security group ids allowed to reach the HTTPS listener (e.g. a VPN or bastion security group), alongside the CloudFront origin-facing prefix list this component always resolves"
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# HTTPS listener. There is no port 80 listener: CloudFront terminates the
# http -> https redirect at the edge, so the ALB only ever needs to answer
# HTTPS.
# ---------------------------------------------------------------------------

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the HTTPS listener. Must be valid for the hostname CloudFront (or any other client) connects with -- see the README for the CloudFront-origin pitfall"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/.+$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN (arn:aws:acm:<region>:<account>:certificate/<id>)."
  }
}

variable "ssl_policy" {
  type        = string
  description = "SSL policy for the HTTPS listener"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "idle_timeout" {
  type        = number
  description = "Connection idle timeout, in seconds"
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection on the load balancer"
  default     = false
}

variable "drop_invalid_header_fields" {
  type        = bool
  description = "Drop HTTP headers with invalid header fields"
  default     = true
}

variable "desync_mitigation_mode" {
  type        = string
  description = "Desync mitigation mode: monitor, defensive or strictest"
  default     = "defensive"

  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode must be one of: monitor, defensive, strictest."
  }
}

variable "enable_http2" {
  type        = bool
  description = "Enable HTTP/2 on the load balancer"
  default     = true
}

# ---------------------------------------------------------------------------
# Default target group. The HTTPS listener's default action forwards to it,
# Cloud Posse aws-alb style, so a later component (ecs-service) can add its
# own target group and a higher-priority listener rule without recreating the
# listener's default action.
# ---------------------------------------------------------------------------

variable "default_target_group_port" {
  type        = number
  description = "Port for the default (catch-all) target group"
  default     = 80
}

variable "default_target_group_protocol" {
  type        = string
  description = "Protocol for the default (catch-all) target group"
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.default_target_group_protocol)
    error_message = "default_target_group_protocol must be HTTP or HTTPS."
  }
}

variable "default_target_group_deregistration_delay" {
  type        = number
  description = "Deregistration delay, in seconds, for the default target group"
  default     = 30
}

# ---------------------------------------------------------------------------
# Access logs. ALB access logs only support SSE-S3 (not the repo's SSE-KMS s3
# component), so this component creates its own dedicated bucket, like Cloud
# Posse's lb-s3-bucket.
# ---------------------------------------------------------------------------

variable "access_logs_enabled" {
  type        = bool
  description = "Create a bucket and enable ALB access logging to it"
  default     = true
}

variable "access_logs_prefix" {
  type        = string
  description = "Key prefix for delivered access log objects"
  default     = ""

  validation {
    condition     = !strcontains(var.access_logs_prefix, "AWSLogs") && can(regex("^[A-Za-z0-9/_.-]*$", var.access_logs_prefix))
    error_message = "access_logs_prefix must not contain \"AWSLogs\" (AWS reserves that path segment for the delivered log objects and rejects a prefix containing it) and may only contain letters, digits, and /_.- ."
  }
}

variable "access_logs_force_destroy" {
  type        = bool
  description = "Let terraform destroy the access-logs bucket even when it holds objects"
  default     = false
}
