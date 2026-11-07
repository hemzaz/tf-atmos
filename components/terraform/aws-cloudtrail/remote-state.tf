module "cloudtrail_bucket" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  component   = var.cloudtrail_bucket_component_name
  environment = var.cloudtrail_bucket_environment_name
  stage       = var.cloudtrail_bucket_stage_name

  context = module.this.context
}

# Remote state lookup for the account-map component (or fallback to static mapping).
#
# When account_map_enabled is true:
#   - Performs remote state lookup to retrieve account mappings from the account-map component
#   - Uses global tenant/environment/stage from iam_roles module for the lookup
#
# When account_map_enabled is false:
#   - Bypasses the remote state lookup (bypass = true)
#   - Returns the static account_map variable as defaults instead
#   - Allows the component to function without the account-map dependency
module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.0"

  component   = var.account_map_component_name
  tenant      = var.account_map_enabled ? module.iam_roles.global_tenant_name : null
  environment = var.account_map_enabled ? module.iam_roles.global_environment_name : null
  stage       = var.account_map_enabled ? module.iam_roles.global_stage_name : null

  context = module.this.context

  # When account_map is disabled, bypass remote state and use the static account_map variable
  bypass   = !var.account_map_enabled
  defaults = var.account_map
}
