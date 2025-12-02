# Security Group Helper Rules and Common Patterns
# Provides pre-defined, secure rule templates for common use cases

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

  # Security validation: Check for overly permissive rules
  ingress_rules_flat = flatten([
    for sg_key, sg_value in local.security_groups : [
      for rule_idx, rule in lookup(sg_value, "ingress_rules", []) : {
        sg_name     = sg_key
        rule_index  = rule_idx
        cidr_blocks = lookup(rule, "cidr_blocks", [])
        from_port   = rule.from_port
        to_port     = rule.to_port
        protocol    = rule.protocol
      }
    ]
  ])

  # Find rules with 0.0.0.0/0 (overly permissive)
  permissive_rules = [
    for rule in local.ingress_rules_flat :
    rule if contains(lookup(rule, "cidr_blocks", []), "0.0.0.0/0")
  ]

  # Validation flags
  has_permissive_rules = length(local.permissive_rules) > 0
  permissive_rule_warning = local.has_permissive_rules ? join(", ", [
    for rule in local.permissive_rules :
    "${rule.sg_name}:${rule.from_port}-${rule.to_port}"
  ]) : ""
}

# CloudWatch Log Group for security group changes
resource "aws_cloudwatch_log_group" "security_group_changes" {
  count = var.enable_security_group_logging ? 1 : 0

  name              = "/aws/securitygroups/${var.tags["Environment"]}/changes"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-sg-changes"
      Purpose = "security-audit"
    }
  )
}

# EventBridge rule to capture security group changes
resource "aws_cloudwatch_event_rule" "security_group_changes" {
  count = var.enable_security_group_logging ? 1 : 0

  name        = "${var.tags["Environment"]}-security-group-changes"
  description = "Capture all security group changes"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName = [
        "AuthorizeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
        "RevokeSecurityGroupEgress",
        "CreateSecurityGroup",
        "DeleteSecurityGroup",
        "ModifySecurityGroupRules"
      ]
    }
  })

  tags = var.tags
}

# CloudWatch Log Stream for security group changes
resource "aws_cloudwatch_log_stream" "security_group_changes" {
  count = var.enable_security_group_logging ? 1 : 0

  name           = "${var.tags["Environment"]}-sg-audit-stream"
  log_group_name = aws_cloudwatch_log_group.security_group_changes[0].name
}

# CloudWatch alarm for overly permissive rules
resource "aws_cloudwatch_metric_alarm" "permissive_sg_rules" {
  count = var.enable_security_group_alarms && local.has_permissive_rules ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-permissive-security-group-rules"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "PermissiveSecurityGroupRules"
  namespace           = "Custom/SecurityGroups"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert on overly permissive security group rules (0.0.0.0/0). Found in: ${local.permissive_rule_warning}"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.security_alarm_actions

  tags = var.tags
}

# Custom metric for tracking permissive rules
resource "aws_cloudwatch_log_metric_filter" "permissive_rules" {
  count = var.enable_security_group_logging && var.enable_security_group_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-permissive-sg-rules"
  log_group_name = aws_cloudwatch_log_group.security_group_changes[0].name
  pattern        = "[...CidrIp=0.0.0.0/0...]"

  metric_transformation {
    name      = "PermissiveSecurityGroupRules"
    namespace = "Custom/SecurityGroups"
    value     = "1"
    default_value = "0"
  }
}

# Validation: Prevent 0.0.0.0/0 in production
resource "null_resource" "validate_no_permissive_rules" {
  count = var.enforce_no_public_ingress && local.has_permissive_rules ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: Security groups have overly permissive rules (0.0.0.0/0): ${local.permissive_rule_warning}' && exit 1"
  }

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
