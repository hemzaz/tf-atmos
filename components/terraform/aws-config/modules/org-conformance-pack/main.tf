locals {
  # Auto-detect if conformance_pack is a URL (http:// or https://) or a local file path
  is_remote_url = can(regex("^https?://", var.conformance_pack))

  # For local paths, resolve relative to the component root directory
  # This module is at modules/org-conformance-pack, so ../../ goes to component root
  template_body = local.is_remote_url ? one(data.http.conformance_pack[*].body) : file("${path.module}/../../${var.conformance_pack}")
}

resource "aws_config_organization_conformance_pack" "default" {
  name = module.this.name

  dynamic "input_parameter" {
    for_each = var.parameter_overrides
    content {
      parameter_name  = input_parameter.key
      parameter_value = input_parameter.value
    }
  }

  template_body = local.template_body

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

data "http" "conformance_pack" {
  count = local.is_remote_url ? 1 : 0
  url   = var.conformance_pack
}
