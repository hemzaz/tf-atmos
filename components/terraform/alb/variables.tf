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

variable "cloudfront_ingress_enabled" {
  type        = bool
  description = "Admit the CloudFront origin-facing managed prefix list on 443 (an ALB behind CloudFront, or a CloudFront VPC origin). Off for an ALB reached directly; it then needs another source: additional_ingress_prefix_list_ids, additional_ingress_security_group_ids or security_group_ids"
  default     = true

  validation {
    condition = var.cloudfront_ingress_enabled || (
      length(var.additional_ingress_prefix_list_ids) + length(var.additional_ingress_security_group_ids) + length(var.security_group_ids) > 0
    )
    error_message = "With cloudfront_ingress_enabled false the ALB admits nothing: set additional_ingress_prefix_list_ids, additional_ingress_security_group_ids or security_group_ids (a group carrying the ingress rules)."
  }
}

variable "route53_health_check_ingress_enabled" {
  type        = bool
  description = "Admit the Route 53 health checkers on 443, from the AWS-managed prefix list com.amazonaws.<region>.route53-healthchecks (weight 25 against the security-group rule quota): for a Route 53 HTTPS health check on a name aliased to this ALB"
  default     = false
}

variable "additional_ingress_prefix_list_ids" {
  type        = list(string)
  description = "Extra managed prefix list ids allowed to reach the HTTPS listener, alongside the CloudFront origin-facing prefix list this component always resolves. Quota note: a security group rule referencing a managed prefix list counts against the 'Rules per security group' quota as that list's max-entries weight, not as 1 -- the CloudFront origin-facing list alone is already ~55-60 of the default 60, so adding an entry here can require an AWS quota increase for that security group."
  default     = []
  nullable    = false
}

variable "additional_ingress_security_group_ids" {
  type        = list(string)
  description = "Extra security group ids allowed to reach the HTTPS listener (e.g. a VPN or bastion security group), alongside the CloudFront origin-facing prefix list this component always resolves. Each entry adds one rule (a security-group reference counts as 1 against the 'Rules per security group' quota, unlike a prefix list) on top of the CloudFront prefix list's ~55 of the default 60 -- see additional_ingress_prefix_list_ids for the quota this shares."
  default     = []
  nullable    = false
}

# Cloud Posse aws-alb's security_group_ids: extra groups attached to the load
# balancer itself (alongside its own), so a target's security group can admit
# the ALB by a group the caller defined in an earlier layer (a securitygroup
# instance) instead of reading this component's own group id.
variable "security_group_ids" {
  type        = list(string)
  description = "Additional security group ids attached to the load balancer, alongside the component's own group (which holds the ingress rules). A target's security group can admit one of these as its source"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "security_group_ids entries must be security group ids (sg-...)."
  }

  validation {
    condition     = length(var.security_group_ids) <= 4
    error_message = "At most 4 security_group_ids: a load balancer takes 5 security groups and the component's own is one."
  }
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

# Cloud Posse terraform-aws-alb's listener_https_fixed_response: the HTTPS
# listener's default action returns this response instead of forwarding to the
# default target group. Behind CloudFront, a 403 here plus listener rules that
# require the distribution's secret origin-verify header (ecs-service
# load_balancer.http_header) refuses every request that did not come through
# the distribution.
variable "listener_https_fixed_response" {
  type = object({
    content_type = string
    message_body = string
    status_code  = string
  })
  description = "Fixed response for the HTTPS listener's default action (content_type, message_body, status_code), replacing the forward to the default target group. Null (default) forwards"
  default     = null

  validation {
    condition = var.listener_https_fixed_response == null || try(
      contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], var.listener_https_fixed_response.content_type)
      && can(regex("^[2-5][0-9][0-9]$", var.listener_https_fixed_response.status_code))
      && length(var.listener_https_fixed_response.message_body) <= 1024,
      false
    )
    error_message = "listener_https_fixed_response needs content_type text/plain, text/css, text/html, application/javascript or application/json, a 2XX-5XX status_code and a message_body of at most 1024 characters."
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

variable "health_check_path" {
  type        = string
  description = "Health check path for the default target group"
  default     = "/"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with /."
  }
}

variable "health_check_matcher" {
  type        = string
  description = "HTTP status code(s) the default target group's health check treats as healthy (e.g. \"200\", \"200-399\"), Cloud Posse terraform-aws-alb default"
  default     = "200-399"
}

variable "health_check_interval" {
  type        = number
  description = "Approximate time, in seconds, between health checks of an individual target"
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "health_check_interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  type        = number
  description = "Time, in seconds, during which no response from a target means a failed health check"
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "health_check_timeout must be between 2 and 120 seconds."
  }
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Number of consecutive successful health checks before an unhealthy target is considered healthy"
  default     = 3

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Number of consecutive failed health checks before a healthy target is considered unhealthy"
  default     = 3

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10."
  }
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

# Cloud Posse aws-alb's lifecycle inputs for the access-logs bucket
# (cloudposse/terraform-aws-lb-s3-bucket).
variable "lifecycle_rule_enabled" {
  type        = bool
  description = "Expire the access logs: expiration_days, noncurrent_version_expiration_days and abort_incomplete_multipart_upload_days"
  default     = false
}

variable "expiration_days" {
  type        = number
  description = "Days after which access log objects expire (lifecycle_rule_enabled)"
  default     = 90

  validation {
    condition     = var.expiration_days >= 1 && floor(var.expiration_days) == var.expiration_days
    error_message = "expiration_days must be a whole number of days, at least 1."
  }
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Days after which noncurrent versions of access log objects expire (lifecycle_rule_enabled; the bucket is versioned)"
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number of days, at least 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  description = "Days after which incomplete multipart uploads are aborted (lifecycle_rule_enabled)"
  default     = 5

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number of days, at least 1."
  }
}

variable "access_logs_force_destroy" {
  type        = bool
  description = "Let terraform destroy the access-logs bucket even when it holds objects"
  default     = false
}

# ---------------------------------------------------------------------------
# Route 53 alias records to the load balancer (Cloud Posse's dns_alias_enabled
# / parent_zone_id, as on the cloudfront component; the names are dns_aliases
# here, since an ALB has no aliases of its own). A CloudFront origin needs
# one: CloudFront checks the origin certificate against the origin hostname,
# and ACM cannot issue for *.elb.amazonaws.com.
# ---------------------------------------------------------------------------

variable "dns_alias_enabled" {
  type        = bool
  description = "Create an A alias record to the load balancer for each of dns_aliases in parent_zone_id"
  default     = false
}

variable "parent_zone_id" {
  type        = string
  description = "Route 53 hosted zone ID the alias records go in (a dns instance's zone_ids.<key>); required with dns_alias_enabled"
  default     = null

  validation {
    condition     = var.parent_zone_id == null || can(regex("^Z[A-Z0-9]{1,31}$", coalesce(var.parent_zone_id, "-")))
    error_message = "parent_zone_id must be a Route 53 hosted zone ID (Z...)."
  }

  validation {
    condition     = !var.dns_alias_enabled || var.parent_zone_id != null && length(var.dns_aliases) > 0
    error_message = "dns_alias_enabled needs parent_zone_id and at least one of dns_aliases."
  }
}

variable "dns_aliases" {
  type        = list(string)
  description = "Fully qualified names (e.g. origin.app.example.com) aliased to the load balancer in parent_zone_id (dns_alias_enabled); certificate_arn must cover them"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.dns_aliases : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", a))])
    error_message = "dns_aliases entries must be lowercase host names without a trailing dot."
  }

  validation {
    condition     = length(distinct(var.dns_aliases)) == length(var.dns_aliases)
    error_message = "dns_aliases entries must be unique."
  }
}
