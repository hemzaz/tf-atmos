# Self-hosted runner pools (the github-runners component).
#
# CI starts an ephemeral in-VPC runner for each in-cluster job by raising its
# pool's desired capacity by one (workflows/scripts/common/start-runner.sh);
# the runner lowers it again when it leaves. Both CI roles start runners: the
# plan role for pull-request plans and drift detection, the apply role for
# deploys. Only groups tagged as runner pools (the github-runners catalog's
# Component tag), so a pull request cannot resize any other group.
locals {
  ci_runner_pool_roles = merge(
    var.github_oidc_enabled ? { plan = aws_iam_role.ci_plan[0].id } : {},
    local.create_ci_apply_role ? { apply = aws_iam_role.ci_apply[0].id } : {},
  )
}

resource "aws_iam_role_policy" "ci_runner_pools" {
  for_each = var.ci_runner_pool_tag == null ? {} : local.ci_runner_pool_roles

  name = "start-ci-runners"
  role = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FindRunnerPools"
        Effect   = "Allow"
        Action   = "autoscaling:DescribeAutoScalingGroups"
        Resource = "*"
      },
      {
        Sid      = "StartRunners"
        Effect   = "Allow"
        Action   = "autoscaling:SetDesiredCapacity"
        Resource = "arn:${data.aws_partition.current.partition}:autoscaling:${var.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/*"
        Condition = {
          StringEquals = { "autoscaling:ResourceTag/${var.ci_runner_pool_tag.key}" = var.ci_runner_pool_tag.value }
        }
      },
    ]
  })
}
