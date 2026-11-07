module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.1"

  component   = var.account_map_component_name
  tenant      = var.account_map_enabled ? coalesce(var.account_map_tenant, module.this.tenant) : null
  stage       = var.account_map_enabled ? var.root_account_stage : null
  environment = var.account_map_enabled ? var.global_environment : null
  privileged  = var.privileged

  context = module.this.context

  bypass   = !var.account_map_enabled
  defaults = var.account_map
}

module "config_bucket" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.1"

  component   = var.config_bucket_component_name
  tenant      = (var.config_bucket_tenant != "") ? var.config_bucket_tenant : module.this.tenant
  stage       = var.config_bucket_stage
  environment = var.config_bucket_env
  privileged  = false

  context = module.this.context
}

module "global_collector_region" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.1"

  count = !local.enabled || local.is_global_collector_region ? 0 : 1

  component   = format(var.global_collector_component_name_pattern, var.config_component_name, lookup(module.utils.region_az_alt_code_maps["to_${var.az_abbreviation_type}"], var.global_resource_collector_region))
  stage       = module.this.stage
  environment = lookup(module.utils.region_az_alt_code_maps["to_${var.az_abbreviation_type}"], var.global_resource_collector_region)
  privileged  = false

  context = module.this.context
}
