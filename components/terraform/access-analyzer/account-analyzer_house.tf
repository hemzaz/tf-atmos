# House file in the vendored Cloud Posse aws-access-analyzer v2.0.1 (vendor.yaml), allowlisted in
# scripts/check-vendor.py HOUSE_FILE_ALLOWLIST (E5c7b, owner 2026-11-18). Deviation from Cloud Posse:
# upstream (cloudposse-terraform-components/aws-access-analyzer) models only the delegated
# administrator's ORGANIZATION and ORGANIZATION_UNUSED_ACCESS analyzers. The external-access ORGANIZATION
# analyzer runs only in the EU security stacks (an externally trusted IAM role is reported in every
# region and that analyzer cannot exclude an account, so a US one would hold prod-eu's IAM findings),
# which leaves US-region resources' external sharing unmonitored. An ACCOUNT analyzer covers one account
# and one region, so each non-GDPR account's US stacks get one (catalog/access-analyzer/account.yaml).
# External-access analyzers are free. Proposed upstream as the same input, resource and output.
variable "accessanalyzer_account_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = <<-DOC
  Create an ACCOUNT external-access analyzer in the account and region the component deploys to
  (analyzer name `<id>-account`). Needs no delegation: any account can create one. Default false, Cloud
  Posse's behaviour.
  DOC
}

resource "aws_accessanalyzer_analyzer" "account" {
  count = local.enabled && var.accessanalyzer_account_enabled ? 1 : 0

  analyzer_name = format("%s-account", module.this.id)
  type          = "ACCOUNT"

  tags = module.this.tags
}

output "account_accessanalyzer_arn" {
  value       = one(aws_accessanalyzer_analyzer.account[*].arn)
  description = "ACCOUNT external-access Access Analyzer ARN"
}
