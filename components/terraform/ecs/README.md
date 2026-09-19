# ecs

Creates an ECS cluster (`aws_ecs_cluster`) with optional Container Insights, plus
capacity provider wiring. When `fargate_only = false`, it also creates an
`aws_ecs_capacity_provider` around an existing Auto Scaling Group and attaches it to
the cluster alongside `FARGATE`/`FARGATE_SPOT`; when `fargate_only = true` (the
default), only the two Fargate capacity providers are attached.

## Deployed instances

Not currently deployed in any of the 3 real stacks (dev, staging, prod) — zero
instances of this component exist today. No stack imports it.

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `tags.Environment` (used for cluster naming) | `fargate_only`, `enable_container_insights`, `autoscaling_group_arn` (required + must be a valid ASG ARN when `fargate_only = false`) | `cluster_id`, `cluster_arn`, `cluster_name`, `capacity_providers` |

## Dependencies & gotchas

- No `dependencies.components` entries exist for this component (it has no
  instances anywhere in the 3 real stacks).
- `autoscaling_group_arn` validation only fires when `fargate_only = false`; leaving
  it blank with `fargate_only = true` (the default) is fine.
- No output of this component is currently consumed via `!terraform.state`
  anywhere in the repo.

## Usage

A stack must add an `ecs/<name>` instance before this is plannable. Once added:

```
atmos terraform plan ecs/main -s fnx-dev-testenv-01
```
