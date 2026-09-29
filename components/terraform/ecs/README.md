# ecs

An ECS cluster with optional Container Insights and its capacity providers: `FARGATE` and
`FARGATE_SPOT` only (`fargate_only = true`, the default), or also an
`aws_ecs_capacity_provider` around an existing Auto Scaling Group (`autoscaling_group_arn`).

## Wiring

- Instance: `ecs/main` in the three AWS stacks and `fnx-local-sandbox`, Fargate only. It lists
  `vpc/main` as a dependency but reads nothing: a cluster has no VPC or subnets (services do).
- Used by: `monitoring/main` (`.cluster_name`). The `web-application` template also configures it.

## Notes

- The name is `cluster_name`, or `<Environment>-cluster` when unset.
- `autoscaling_group_arn` is required and validated only when `fargate_only = false`.
