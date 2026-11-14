# House file in the vendored Cloud Posse aws-access-analyzer v2.0.1 (vendor.yaml), allowlisted in
# scripts/check-vendor.py HOUSE_FILE_ALLOWLIST (E5c7, owner decision 2026-11-14). The unused-access
# analyzer is global (AWS: its findings "do not change based on Region"), so one in us-east-1 holds
# every member account's IAM metadata. CP's analyzer has no analysis rule; this input excludes
# accounts from it, so the US analyzer leaves out the all-GDPR accounts (prod-eu) and the EU one
# (fnx-ew1-security) analyses only them (EU data stays in the EU). unused-access_override.tf adds the
# rule to CP's aws_accessanalyzer_analyzer.organization_unused_access. Accounts are account-map
# names, resolved from the same map the component uses (as aws-security-hub's
# account-suppressions_house.tf).
variable "unused_access_exclusion_account_names" {
  type        = list(string)
  default     = []
  description = <<-DOC
  Account map names (keys of account_map.full_account_map) the organization unused-access analyzer
  excludes (configuration.unused_access.analysis_rule.exclusion.account_ids): those accounts' IAM
  users and roles generate no findings. Empty (default): no analysis rule, Cloud Posse's behaviour.
  AWS allows at most 2,000 account IDs and never the analyzer owner account (the delegated
  administrator the analyzer runs in).
  DOC

  validation {
    condition     = length(var.unused_access_exclusion_account_names) <= 2000
    error_message = "At most 2,000 accounts (AWS AnalysisRuleCriteria accountIds)."
  }
  validation {
    condition     = length(distinct(var.unused_access_exclusion_account_names)) == length(var.unused_access_exclusion_account_names)
    error_message = "Each account is listed once."
  }
  validation {
    condition     = alltrue([for name in var.unused_access_exclusion_account_names : contains(keys(local.account_map), name)])
    error_message = "Every entry must be a key of account_map.full_account_map."
  }
  # The owner is the delegated administrator (only it creates organization analyzers; CP's account
  # verification pins the run to it), compared by name: known at plan, with no AWS call, and not
  # fooled by placeholder account IDs that are all equal.
  validation {
    condition     = !contains(var.unused_access_exclusion_account_names, var.delegated_administrator_account_name)
    error_message = "The list may not name the analyzer owner account (delegated_administrator_account_name): AWS rejects it."
  }
}

locals {
  unused_access_exclusion_account_ids = [
    for name in var.unused_access_exclusion_account_names : lookup(local.account_map, name, null)
  ]
}
