# House file in the vendored Cloud Posse aws-security-hub v2.2.1 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST (E5c, owner
# decision 2026-11-10). CP's disabled_control_finding_reasons suppresses a
# control's findings for every account; these rules also filter by account, so
# an administrator can suppress a control for the accounts that cannot pass it
# in this region while another account's findings stay (fnx-ew1-security: the
# shared accounts record IAM and keep their trail in us-east-1, prod-eu in
# eu-west-1). Same gate and action as CP's automation-rules.tf. Accounts are
# account-map names, resolved from the same map the component uses.
variable "account_scoped_control_suppressions" {
  type = map(object({
    control_ids     = list(string)
    account_names   = list(string)
    disabled_reason = string
    rule_order      = optional(number, 1)
  }))
  default     = {}
  description = <<-DOC
  Security Hub automation rules (delegated administrator, org-settings step) that set FAILED,
  ACTIVE findings of control_ids to SUPPRESSED only in the accounts account_names name (keys of
  the account map). AWS limits a rule to 20 control IDs and 100 account IDs.
  DOC

  validation {
    condition = alltrue([for v in values(var.account_scoped_control_suppressions) :
    length(v.control_ids) > 0 && length(v.control_ids) <= 20 && length(v.account_names) > 0 && length(v.account_names) <= 100])
    error_message = "Each entry needs 1-20 control_ids and 1-100 account_names (AWS automation rule criteria limits)."
  }
  validation {
    condition     = alltrue([for v in values(var.account_scoped_control_suppressions) : trimspace(v.disabled_reason) != ""])
    error_message = "Each entry needs a non-empty disabled_reason."
  }
}

resource "aws_securityhub_automation_rule" "suppress_account_control_findings" {
  for_each = local.create_org_configuration ? var.account_scoped_control_suppressions : {}

  rule_name   = "Suppress ${each.key}"
  description = each.value.disabled_reason
  rule_order  = each.value.rule_order
  rule_status = "ENABLED"
  is_terminal = true

  criteria {
    dynamic "aws_account_id" {
      for_each = toset(each.value.account_names)
      content {
        comparison = "EQUALS"
        value      = local.account_map[aws_account_id.value]
      }
    }

    dynamic "compliance_security_control_id" {
      for_each = toset(each.value.control_ids)
      content {
        comparison = "EQUALS"
        value      = compliance_security_control_id.value
      }
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
