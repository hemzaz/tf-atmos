module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.1"

  component   = var.account_map_component_name
  tenant      = var.account_map_enabled ? coalesce(var.account_map_tenant, module.this.tenant) : null
  stage       = var.account_map_enabled ? var.root_account_stage : null
  environment = var.account_map_enabled ? var.global_environment : null
  privileged  = var.privileged

  context = module.this.context

  # When account_map is disabled, bypass remote state and use the static account_map variable
  bypass   = !var.account_map_enabled
  defaults = var.account_map
}
