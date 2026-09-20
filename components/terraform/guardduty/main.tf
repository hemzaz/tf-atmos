locals {
  name_prefix = "${var.tags["Environment"]}-guardduty"

  # On AWS provider 6.x the detector no longer takes inline `datasources` blocks;
  # each protection plan is its own aws_guardduty_detector_feature resource.
  features = {
    S3_DATA_EVENTS         = var.enable_s3_protection
    EKS_AUDIT_LOGS         = var.enable_kubernetes_protection
    EBS_MALWARE_PROTECTION = var.enable_malware_protection
  }
}

resource "aws_guardduty_detector" "main" {
  # checkov:skip=CKV2_AWS_3: Deliberate scope limit, not a false positive. The check wants the
  # detector wired to an aws_guardduty_organization_configuration with org-wide auto-enrollment.
  # That resource may only be created by the Organizations delegated administrator account, this
  # component deploys into a member account, and no stack here asks for org-wide enrollment.
  count = var.enable ? 1 : 0

  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  tags = { Name = local.name_prefix }
}

resource "aws_guardduty_detector_feature" "main" {
  for_each = var.enable ? local.features : {}

  detector_id = aws_guardduty_detector.main[0].id
  name        = each.key
  status      = each.value ? "ENABLED" : "DISABLED"
}

# Findings matching a filter with action ARCHIVE are suppressed from the active
# finding list; rank decides evaluation order when several filters overlap.
resource "aws_guardduty_filter" "auto_archive" {
  count = var.enable ? length(var.auto_archive_filter) : 0

  name        = "${local.name_prefix}-auto-archive-${count.index + 1}"
  action      = "ARCHIVE"
  detector_id = aws_guardduty_detector.main[0].id
  rank        = count.index + 1

  finding_criteria {
    criterion {
      field  = "severity"
      equals = [tostring(var.auto_archive_filter[count.index].severity)]
    }

    dynamic "criterion" {
      for_each = var.auto_archive_filter[count.index].criteria

      content {
        field  = criterion.key
        equals = criterion.value
      }
    }
  }

  tags = { Name = "${local.name_prefix}-auto-archive-${count.index + 1}" }
}
