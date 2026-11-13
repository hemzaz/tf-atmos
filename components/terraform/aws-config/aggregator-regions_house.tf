# House file in the vendored Cloud Posse aws-config v3.1.1 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST (E5c3b, owner
# decision 2026-11-13: the shared accounts' eu-central-1 Config data stays in
# the EU). Cloud Posse's config module 1.5.3 creates the account aggregator
# with all_regions = true and takes no regions input, and an aggregator may
# read its own account's data in every region, so a US aggregator (in the
# security account) would read that account's EU regions too. Set
# aggregator_regions and this instance's aggregation goes through here
# instead: aggregator-regions_override.tf disables the module's aggregation
# resources in this region (its disabled_aggregation_regions), and this file
# creates what they would have, the aggregator over the named regions only
# (central account, global-resource collector region, as the module) and the
# region's authorization to the central account. Upstream: a regions input
# for account_aggregation_source (open a PR against cloudposse/terraform-aws-config).
variable "aggregator_regions" {
  type        = list(string)
  default     = null
  description = <<-DOC
  The source regions of the account aggregator (AccountAggregationSource.AwsRegions) in place of
  Cloud Posse's all_regions. null keeps Cloud Posse's aggregation unchanged.
  DOC

  validation {
    condition = var.aggregator_regions == null ? true : (
      length(var.aggregator_regions) > 0
      && alltrue([for r in var.aggregator_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    )
    error_message = "aggregator_regions must be null or a non-empty list of AWS region names."
  }
}

locals {
  house_aggregation = local.enabled && var.aggregator_regions != null
  house_aggregator  = local.house_aggregation && local.is_global_collector_region && local.current_account_id == local.central_resource_collector_account
}

module "aws_config_aggregator_label" {
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  attributes = ["config", "aggregator"]

  context = module.this.context
}

# Cloud Posse's aws_config_configuration_aggregator.this (config 1.5.3 main.tf), regions named.
resource "aws_config_configuration_aggregator" "regions" {
  #checkov:skip=CKV_AWS_121:the aggregator names its regions on purpose (owner 2026-11-13: EU Config data is never aggregated outside the EU); every recorder still records in its region
  count = local.house_aggregator ? 1 : 0

  name = module.aws_config_aggregator_label.id

  account_aggregation_source {
    account_ids = local.delegated_accounts
    regions     = var.aggregator_regions
  }

  tags = module.this.tags
}

# Cloud Posse's aws_config_aggregate_authorization.child, which the override disables with the rest
# of the module's aggregation in this region.
resource "aws_config_aggregate_authorization" "regions" {
  count = local.house_aggregation ? 1 : 0

  account_id = local.central_resource_collector_account
  region     = var.global_resource_collector_region

  tags = module.this.tags
}
