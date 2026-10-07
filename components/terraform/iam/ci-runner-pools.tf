# Self-hosted runner pools (the github-runners component).
#
# CI starts an ephemeral in-VPC runner for each in-cluster job by executing
# its pool's start policy (<group>-start, a SimpleScaling +1 that Auto Scaling
# caps at max_size; workflows/scripts/common/start-runner.sh); the runner
# leaves its group when done. Only the apply role starts runners: every
# in-VPC job (plan, drift, deploy) runs on the default branch with it (owner
# decision), so the plan role, which trusts pull requests, has no write here.
# ExecutePolicy only, on this stack's own pools by name: CI cannot set a
# capacity (no SetDesiredCapacity: not 0 mid-apply, not max), nor touch any
# other group.
resource "aws_iam_role_policy" "ci_runner_pools" {
  count = local.create_ci_apply_role && length(var.ci_runner_pool_names) > 0 ? 1 : 0

  name = "start-ci-runners"
  role = aws_iam_role.ci_apply[0].name
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
