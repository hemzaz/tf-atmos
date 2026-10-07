locals {
  # Security Hub subscribes these two itself when enable_default_standards is set.
  # Subscribing again would collide on apply, so they are dropped from the explicit
  # set instead of forcing every caller to know which standards are implicit.
  auto_enabled_standards = [
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/1.2.0",
  ]

  # CIS v1.2.0 predates the regional standards namespace and is the only standard
  # addressed through the partition-wide ruleset path.
  ruleset_standards = ["cis-aws-foundations-benchmark/v/1.2.0"]

  standards = var.enable ? toset([
    for standard in var.standards : standard
    if !(var.enable_default_standards && contains(local.auto_enabled_standards, standard))
  ]) : toset([])

  standards_arns = {
    for standard in distinct(concat(var.standards, local.auto_enabled_standards, keys(var.disabled_security_controls))) :
    standard => contains(local.ruleset_standards, standard) ? "arn:aws:securityhub:::ruleset/${standard}" : "arn:aws:securityhub:${var.region}::standards/${standard}"
  }

  # One association per (standard, control) in disabled_security_controls.
  disabled_control_associations = var.enable ? {
    for pair in flatten([
      for standard, ids in var.disabled_security_controls : [
        for id in ids : { standard = standard, security_control_id = id }
      ]
    ]) : "${pair.standard}|${pair.security_control_id}" => pair
  } : {}
}

resource "aws_securityhub_account" "main" {
  count = var.enable ? 1 : 0

  enable_default_standards = var.enable_default_standards

  # Consolidated findings: one finding per control check rather than one per
  # standard, so a control shared by several standards is not reported N times.
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

resource "aws_securityhub_standards_subscription" "main" {
  for_each = local.standards

  depends_on = [aws_securityhub_account.main]

  standards_arn = local.standards_arns[each.value]
}

# Controls turned off in one standard each (consolidated control findings:
# the association of a security control with a standard). The DR region's
# instance uses it for the controls that check global resources (IAM), which
# AWS says to disable outside the region that records them (AWS Config
# include_global_resource_types, fnx-ue1-prod only).
resource "aws_securityhub_standards_control_association" "disabled" {
  for_each = local.disabled_control_associations

  depends_on = [aws_securityhub_account.main, aws_securityhub_standards_subscription.main]

  standards_arn       = local.standards_arns[each.value.standard]
  security_control_id = each.value.security_control_id
  association_status  = "DISABLED"
  updated_reason      = var.disabled_security_controls_reason
}
