# Plan-time audit of the rules this component creates: a detector for ingress
# open to the whole internet (0.0.0.0/0 or ::/0), the enforce_no_public_ingress
# guard built on it, and a set of rule templates offered as an output for
# reference.
#
# Security group CHANGE detection is not here: it is an account-and-region
# concern, owned by security-monitoring (an EventBridge rule per change and the
# CIS SecurityGroupChanges metric filter and alarm, both to its KMS-encrypted
# alert topic). This component used to create its own log group, EventBridge
# rule, metric filter and alarm per instance; the rule had no target, the
# filter could never match CloudTrail's JSON, and the names collided between
# instances, so none of it ever alerted.
#
# The rules this component actually creates are in main.tf; what is normalized
# and keyed for them is in normalize.tf.

locals {
  # Common security group rule templates
  common_rules = {
    # HTTPS from VPC
    https_from_vpc = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS from VPC"
    }

    # HTTP from VPC (discouraged, use HTTPS)
    http_from_vpc = {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP from VPC (use HTTPS instead)"
    }

    # SSH from bastion
    ssh_from_bastion = {
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH from bastion host"
    }

    # MySQL/Aurora from app tier
    mysql_from_app = {
      type        = "ingress"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      description = "MySQL access from application tier"
    }

    # PostgreSQL from app tier
    postgres_from_app = {
      type        = "ingress"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from application tier"
    }

    # Redis from app tier
    redis_from_app = {
      type        = "ingress"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      description = "Redis access from application tier"
    }

    # All outbound to VPC
    all_outbound_vpc = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All outbound to VPC CIDR"
    }

    # HTTPS outbound (for API calls)
    https_outbound = {
      type        = "egress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS outbound for AWS API calls"
    }

    # HTTP outbound (for updates, discouraged)
    http_outbound = {
      type        = "egress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP outbound (use HTTPS instead)"
    }

    # NFS from VPC
    nfs_from_vpc = {
      type        = "ingress"
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      description = "NFS access from VPC"
    }

    # SMTP outbound
    smtp_outbound = {
      type        = "egress"
      from_port   = 587
      to_port     = 587
      protocol    = "tcp"
      description = "SMTP outbound for email"
    }

    # DNS outbound
    dns_outbound = {
      type        = "egress"
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      description = "DNS outbound"
    }

    # LDAP from VPC
    ldap_from_vpc = {
      type        = "ingress"
      from_port   = 389
      to_port     = 389
      protocol    = "tcp"
      description = "LDAP access from VPC"
    }

    # LDAPS from VPC
    ldaps_from_vpc = {
      type        = "ingress"
      from_port   = 636
      to_port     = 636
      protocol    = "tcp"
      description = "LDAPS access from VPC"
    }
  }

  # Security validation: check for overly permissive rules.
  #
  # Read from the normalized rules in normalize.tf, not from var.security_groups
  # directly: that is the same list the aws_security_group_rule resources are
  # built from, so a rule cannot be created without passing under this check.
  # The previous version walked the raw variable with lookup(rule,
  # "cidr_blocks", []), which returns null -- not [] -- for a rule that declares
  # the attribute and leaves it unset, and contains(null, ...) is an error. Any
  # rule sourced from a security group rather than a CIDR crashed the plan.
  permissive_rules = [
    for key, r in local.keyed_rules : {
      sg_name     = r.sg_key
      rule_key    = key
      from_port   = r.from_port
      to_port     = r.to_port
      protocol    = r.protocol
      cidr_blocks = concat(r.cidr_blocks, r.ipv6_cidr_blocks)
    }
    # ::/0 is as open as 0.0.0.0/0 and was not checked before.
    if r.type == "ingress" && (contains(r.cidr_blocks, "0.0.0.0/0") || contains(r.ipv6_cidr_blocks, "::/0"))
  ]

  # Validation flags
  has_permissive_rules = length(local.permissive_rules) > 0
  permissive_rule_warning = local.has_permissive_rules ? join(", ", [
    for rule in local.permissive_rules :
    "${rule.rule_key} (${rule.from_port}-${rule.to_port})"
  ]) : ""
}

# Validation: Prevent 0.0.0.0/0 in production
# (the precondition fails the plan; no provisioner or null provider needed)
resource "terraform_data" "validate_no_permissive_rules" {
  count = var.enforce_no_public_ingress ? 1 : 0

  lifecycle {
    precondition {
      condition     = !local.has_permissive_rules || !var.enforce_no_public_ingress
      error_message = "Security groups cannot have ingress rules with 0.0.0.0/0 CIDR block when enforce_no_public_ingress is enabled. Found permissive rules in: ${local.permissive_rule_warning}"
    }
  }
}

# Helper outputs for rule templates
output "common_rule_templates" {
  description = "Common security group rule templates for reference"
  value       = local.common_rules
}

output "security_validation_warnings" {
  description = "Security validation warnings for overly permissive rules"
  value = {
    has_permissive_rules = local.has_permissive_rules
    permissive_rules     = local.permissive_rules
    warning_message      = local.has_permissive_rules ? "WARNING: Found ${length(local.permissive_rules)} overly permissive security group rules with 0.0.0.0/0" : "No overly permissive rules detected"
  }
}

# Documentation comment block for common patterns
/*
COMMON SECURITY GROUP PATTERNS:

1. Web Tier (Public ALB):
   - Ingress: 443 from 0.0.0.0/0 (HTTPS only, no HTTP)
   - Egress: All to App Tier SG

2. Application Tier:
   - Ingress: App port from Web Tier SG
   - Egress: Database port to DB Tier SG, 443 to 0.0.0.0/0 (AWS APIs)

3. Database Tier:
   - Ingress: DB port from App Tier SG
   - Egress: None (or minimal for updates via VPC endpoints)

4. Bastion/Jump Host:
   - Ingress: 22 from corporate IP CIDR (NOT 0.0.0.0/0)
   - Egress: 22 to VPC CIDR

5. Lambda:
   - Ingress: None (unless triggered by ALB/API Gateway)
   - Egress: 443 to 0.0.0.0/0, DB port to DB Tier SG

BEST PRACTICES:
- Use specific CIDR blocks, NOT 0.0.0.0/0 for ingress
- Reference security groups instead of CIDR blocks when possible
- Use VPC endpoints to avoid 0.0.0.0/0 egress
- Document the purpose of each rule
- Regularly audit and remove unused rules
- Use separate security groups per tier
- Never allow SSH (22) or RDP (3389) from 0.0.0.0/0
*/
