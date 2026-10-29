module "vpc" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.1"

  for_each = local.private_enabled ? local.vpc_environment_names : toset([])

  component   = var.vpc_component_name
  environment = each.value

  context = module.this.context
}

module "private_ca" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.1"

  count = local.private_ca_enabled && local.certificate_enabled ? 1 : 0

  component   = var.certificate_authority_component_name
  stage       = var.certificate_authority_stage_name
  environment = var.certificate_authority_environment_name

  context = module.this.context
}
