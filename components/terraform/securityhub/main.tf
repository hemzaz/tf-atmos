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

  standards_arn = contains(local.ruleset_standards, each.value) ? "arn:aws:securityhub:::ruleset/${each.value}" : "arn:aws:securityhub:${var.region}::standards/${each.value}"
}
