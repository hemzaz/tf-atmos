# Amazon Inspector for one account and region, modelled on Cloud Posse
# aws-inspector2 (cloudposse-terraform-components/aws-inspector2). Deviation:
# only the single-account path. Cloud Posse's component delegates the
# Inspector administrator from the organization management account and, in the
# delegated administrator account, sets the organization's auto-enable and
# associates members. This repo has no AWS Organizations management or
# delegated-administrator stack, so each workload account enables itself here,
# with the resource types the auto_enable_* flags select.
locals {
  resource_types = compact([
    var.auto_enable_ec2 ? "EC2" : null,
    var.auto_enable_ecr ? "ECR" : null,
    var.auto_enable_lambda ? "LAMBDA" : null,
    var.auto_enable_lambda_code ? "LAMBDA_CODE" : null,
  ])
}

data "aws_caller_identity" "current" {
  count = var.enabled ? 1 : 0
}

resource "aws_inspector2_enabler" "main" {
  count = var.enabled ? 1 : 0

  account_ids    = [data.aws_caller_identity.current[0].account_id]
  resource_types = local.resource_types
}
