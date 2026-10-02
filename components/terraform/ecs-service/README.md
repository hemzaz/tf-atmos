# ecs-service

An ECS service (Fargate by default, or EC2) with its task definition, a KMS-encrypted log group
(`/ecs/<Environment>-<name>`), an execution role and an optional task role, plus an optional ALB
target group and listener rule and optional target-tracking autoscaling. It models a subset of
Cloud Posse's `aws-ecs-service` component (`terraform-aws-ecs-alb-service-task` and
`terraform-aws-ecs-container-definition`) and keeps their input names where they fit
(`ecs_cluster_arn`, `task_cpu`, `task_memory`, `containers`, `task_exec_role_arn`,
`task_role_arn`, `task_policy_arns`, `exec_enabled`, `circuit_breaker_*`, ...). Deviations are
commented beside the code.

## Wiring

- No instance in the fnx stacks. `ecs-service/defaults` is the abstract base and reads
  `log_kms_key_arn` from `kms/main` (its key policy must allow CloudWatch Logs,
  `allow_cloudwatch_logs`, on in `catalog/kms/defaults`).
- An instance sets `ecs_cluster_arn` (an `ecs` instance's `.cluster_arn`), `subnet_ids`
  (`vpc/main .private_subnet_ids`) and `security_group_ids` (a `securitygroup` instance's ids),
  and lists those instances in `dependencies.components`. With `load_balancer` it also reads an
  `alb` instance (`listener_arn` = `.https_listener_arn`) and `vpc/main .vpc_id`. It deploys in
  the `services` layer of `workflows/deploy-full-stack.yaml`, after `ecs` (compute).
- Consumers: `monitoring` reads `.service_name` (with the cluster's `.cluster_name`) for the
  `AWS/ECS` dimensions and `.target_group_arn_suffix` for `AWS/ApplicationELB` ones.
- `stacks/catalog/templates/web-application.yaml` predates this component (raw
  `task_definition`/`container_definitions`, `cluster_arn`, `enable_autoscaling`); it needs
  porting to `containers`, `ecs_cluster_arn`, `load_balancer` and `autoscaling`.

## Notes

- The network mode is always `awsvpc`, so target groups use `ip` targets for Fargate and EC2
  alike, and `host_port` must be unset or equal `container_port`.
- The component creates no security group: inbound rules belong to the `securitygroup` instance
  it is given (from the ALB's security group, never `0.0.0.0/0`).
- `assign_public_ip` is false: the subnets need a NAT gateway or VPC endpoints (ECR API/DKR, S3,
  Logs, Secrets Manager/SSM) to pull images, log and read secrets.
- Fargate takes only the documented `task_cpu`/`task_memory` pairs; EC2 may leave both unset when
  every container sets `memory` or `memory_reservation`.
- `capacity_provider_strategies` replaces `launch_type` on the service: `FARGATE`/`FARGATE_SPOT`
  for Fargate, the cluster's Auto Scaling group providers for EC2.
- The execution role (`<Environment>-<name>-task-execution`, or `task_exec_role_arn`) pulls from
  `ecr_repository_arns` (every repository when empty), logs only to the component log group, and
  reads exactly the containers' secrets (Secrets Manager secret ARNs without the json-key tail,
  SSM parameter ARNs; `kms:Decrypt` on `secrets_kms_key_arn` through those two services).
  Containers log with `awslogs` to that group only, stream prefix = the container name.
- `secrets` take full Secrets Manager ARNs with the 6-character suffix, since the IAM grant is the
  exact ARN.
- The task role (`<Environment>-<name>-task`) exists only with `task_policy_arns`,
  `task_policy_json` or `exec_enabled`, unless `task_role_arn` is given; otherwise the containers
  have no AWS credentials.
- Both roles trust `ecs-tasks.amazonaws.com` with `aws:SourceAccount`; the task role also requires
  `aws:SourceArn` like `arn:aws:ecs:<region>:<account>:*`. The execution role does not (the ECS
  docs show none, and a missing one would fail every task at start). A role given by ARN needs a
  trust that allows ECS tasks.
- `exec_enabled` gives the created task role the `ssmmessages` permissions and `kms:Decrypt` on
  `exec_kms_key_arn` (the cluster's ECS Exec key, when it sets one; the `ecs` component sets none
  today). A `task_role_arn` must grant them itself.
- Root filesystems are read-only by default (`readonly_root_filesystem`): a container that writes
  to local disk (`/tmp` included) needs `false`, since the component mounts no volumes.
- With `autoscaling` the service ignores `desired_count` after creation, and the service is a
  different resource: switching autoscaling on or off replaces the service (Cloud Posse's
  `ignore_changes_desired_count` pattern). `alb_request_count_per_target` needs `load_balancer`.
- Every task definition change registers a new revision and rolls the service; the deployment
  circuit breaker (on, with rollback) returns to the last working revision if tasks fail.
- The target group name is `<Environment>-<name>` (32 characters at most). Changing its port,
  protocol or VPC replaces it, which fails while the listener rule still forwards to it: change
  the rule (or remove `load_balancer`) first.
- The listener rule's `priority` must be unique on the listener.
- Part 2, not here: service connect and service discovery, blue-green deployments
  (`CODE_DEPLOY`), more than one target group, sidecars beyond the `containers` map
  (`dependsOn`, FireLens), and EFS or other volumes.
