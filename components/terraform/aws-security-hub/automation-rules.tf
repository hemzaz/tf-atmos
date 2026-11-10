# Security Hub automation rules to suppress known false-positive control findings.
# Rules are created in the delegated administrator account and apply org-wide.

resource "aws_securityhub_automation_rule" "suppress_control_findings" {
  for_each = local.create_org_configuration ? var.disabled_control_finding_reasons : {}

  rule_name   = "Suppress ${each.value.control_id}${each.value.reason_code != null ? " (${each.value.reason_code})" : ""}"
  description = each.value.disabled_reason
  rule_order  = each.value.rule_order
  rule_status = "ENABLED"
  is_terminal = true

  criteria {
    compliance_security_control_id {
      comparison = "EQUALS"
      value      = each.value.control_id
    }

    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }

    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
  }

  actions {
    type = "FINDING_FIELDS_UPDATE"

    finding_fields_update {
      workflow {
        status = "SUPPRESSED"
      }

      note {
        text       = each.value.disabled_reason
        updated_by = "terraform-securityhub-automation"
      }
    }
  }
}
