# Self-hosted runner pools (the github-runners component).
#
# CI starts an ephemeral in-VPC runner for each in-cluster job by executing
# its pool's start policy (<group>-start, a SimpleScaling +1 that Auto Scaling
# caps at max_size; workflows/scripts/common/start-runner.sh); the runner
# leaves its group when done. Both CI roles start runners: the plan role for
# pull-request plans and drift detection, the apply role for deploys.
# ExecutePolicy only, on this stack's own pools by name: CI cannot set a
# capacity (no SetDesiredCapacity: not 0 mid-apply, not max), nor touch any
# other group. The policy is the only write the plan role has.
locals {
  ci_runner_pool_roles = merge(
    var.github_oidc_enabled ? { plan = aws_iam_role.ci_plan[0].id } : {},
    local.create_ci_apply_role ? { apply = aws_iam_role.ci_apply[0].id } : {},
  )
}

resource "aws_iam_role_policy" "ci_runner_pools" {
  for_each = length(var.ci_runner_pool_names) == 0 ? {} : local.ci_runner_pool_roles

  name = "start-ci-runners"
  role = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartRunners"
        Effect = "Allow"
        Action = "autoscaling:ExecutePolicy"
        Resource = [
          for name in var.ci_runner_pool_names :
          "arn:${data.aws_partition.current.partition}:autoscaling:${var.region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${name}"
        ]
      },
    ]
  })
}
