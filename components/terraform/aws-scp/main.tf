locals {
  enabled     = module.this.enabled
  policy_name = coalesce(var.policy_name, module.this.id, "default-policy")

  # Combine deprecated target_id (single string) with target_ids (list)
  all_target_ids = distinct(concat(
    var.target_ids,
    var.target_id != null ? [var.target_id] : []
  ))

  generated_policy = length(var.policy_statements) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in var.policy_statements : merge(
        {
          Effect = stmt.effect
        },
        length(coalesce(stmt.resources, [])) > 0 ? { Resource = stmt.resources } : {},
        length(coalesce(stmt.not_resources, [])) > 0 ? { NotResource = stmt.not_resources } : {},
        length(stmt.actions) > 0 ? { Action = stmt.actions } : {},
        length(stmt.not_actions) > 0 ? { NotAction = stmt.not_actions } : {},
        stmt.sid != null ? { Sid = stmt.sid } : {},
        length(coalesce(stmt.conditions, [])) > 0 ? {
          Condition = {
            for test_key in distinct([for c in coalesce(stmt.conditions, []) : c.test]) : test_key => merge([
              for cond in [for c in coalesce(stmt.conditions, []) : c if c.test == test_key] : {
                (cond.variable) = cond.values
              }
            ]...)
          }
        } : {}
      )
    ]
  }) : null

  policy_content = coalesce(var.policy_content, local.generated_policy, jsonencode({
    Version   = "2012-10-17"
    Statement = []
  }))
}

resource "aws_organizations_policy" "this" {
  count = local.enabled ? 1 : 0

  name        = local.policy_name
  description = var.policy_description
  content     = local.policy_content
  type        = "SERVICE_CONTROL_POLICY"
  tags        = module.this.tags
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.enabled && var.attach_to_target ? toset(local.all_target_ids) : toset([])

  policy_id = aws_organizations_policy.this[0].id
  target_id = each.value

  lifecycle {
    precondition {
      condition     = !var.attach_to_target || length(local.all_target_ids) > 0
      error_message = "target_ids must not be empty when attach_to_target is true. This can happen when a !terraform.output reference resolves to null."
    }
  }
}
