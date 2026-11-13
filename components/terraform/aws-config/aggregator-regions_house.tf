# House file in the vendored Cloud Posse aws-config v3.1.1 (vendor.yaml),
# allowlisted in scripts/check-vendor.py HOUSE_FILE_ALLOWLIST (E5c3b, owner
# decisions 2026-11-13: Config data of an EU region is aggregated only in the
# EU, and the shared accounts' EU recorders report to the EU aggregator,
# fnx-ew1-security, without a second IAM recording). Cloud Posse's config
# module 1.5.3 lacks both knobs:
#   - its account aggregator has all_regions = true and no regions input, and
#     an aggregator may read its own account's data in every region;
#   - a recorder authorizes (central account, global_resource_collector_region),
#     and that region also decides whether it records IAM (the collector).
# So, per instance:
#   - aggregator_regions: the aggregator (central account, collector region,
#     as the module) over the named regions only;
#   - aggregator_authorization_region: the region whose aggregator this
#     recorder authorizes, in place of its collector region (a shared account's
#     EU recorder keeps its US home collector region, recording no IAM, and
#     authorizes the EU aggregator in eu-west-1).
# With either set, aggregator-regions_override.tf turns the module's
# aggregation resources off in this region (its own disabled_aggregation_regions:
# its aggregator and both authorizations, config 1.5.3 main.tf), and this file
# creates their replacement: exactly one authorization, to (central account,
# aggregator_authorization_region, else the collector region), and the
# aggregator where the module would create it. Upstream PR: inputs for both.
variable "aggregator_regions" {
  type        = list(string)
  default     = null
  description = <<-DOC
  The source regions of the account aggregator (AccountAggregationSource.AwsRegions) in place of
  Cloud Posse's all_regions. null keeps Cloud Posse's aggregator.
  DOC

  validation {
    condition = var.aggregator_regions == null ? true : (
      length(var.aggregator_regions) > 0
      && alltrue([for r in var.aggregator_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    )
    error_message = "aggregator_regions must be null or a non-empty list of AWS region names."
  }
}

variable "aggregator_authorization_region" {
  type        = string
  default     = null
  description = <<-DOC
  The region of the central account's aggregator this recorder authorizes, in place of
  global_resource_collector_region (which still decides the IAM recording). null keeps Cloud
  Posse's authorization.
  DOC

  validation {
    condition     = var.aggregator_authorization_region == null ? true : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aggregator_authorization_region))
    error_message = "aggregator_authorization_region must be null or an AWS region name."
  }
}

locals {
  house_aggregation          = local.enabled && (var.aggregator_regions != null || var.aggregator_authorization_region != null)
  house_authorization_region = coalesce(var.aggregator_authorization_region, var.global_resource_collector_region)
  house_aggregator           = local.house_aggregation && var.aggregator_regions != null && local.is_global_collector_region && local.current_account_id == local.central_resource_collector_account
}

module "aws_config_aggregator_label" {
  #checkov:skip=CKV_TF_1:a registry module pinned to an exact version, the same cloudposse/label/null 0.25.0 the vendored main.tf and config module use
  source     = "cloudposse/label/null"
  version    = "0.25.0"
  attributes = ["config", "aggregator"]

  context = module.this.context
}

# Cloud Posse's aws_config_configuration_aggregator.this (config 1.5.3 main.tf), regions named.
resource "aws_config_configuration_aggregator" "regions" {
  #checkov:skip=CKV_AWS_121:the aggregator names its regions on purpose (owner 2026-11-13: Config data of a region is aggregated only in its residency); every recorder still records in its region
  count = local.house_aggregator ? 1 : 0

  name = module.aws_config_aggregator_label.id

  account_aggregation_source {
    account_ids = local.delegated_accounts
    regions     = var.aggregator_regions
  }

  tags = module.this.tags
}

# Cloud Posse's aws_config_aggregate_authorization.child, which the override disables with the rest
# of the module's aggregation in this region, to the house authorization region.
resource "aws_config_aggregate_authorization" "regions" {
  count = local.house_aggregation ? 1 : 0

  account_id = local.central_resource_collector_account
  region     = local.house_authorization_region

  tags = module.this.tags
}
