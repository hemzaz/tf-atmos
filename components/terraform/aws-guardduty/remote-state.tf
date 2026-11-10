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

module "guardduty_delegated_detector" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "1.8.1"

  # If we are creating the delegated detector (because we are in the delegated admin account), then don't try to lookup
  # the delegated detector ID from remote state
  count = local.create_guardduty_collector ? 0 : 1

  component = var.delegated_administrator_component_name
  # delegated_administrator_account_name is in "tenant-stage" format (e.g. "core-security"),
  # but the remote-state module inherits tenant from context, so we only need the stage part.
  stage      = element(split("-", var.delegated_administrator_account_name), 1)
  privileged = var.privileged

  context = module.this.context
}
