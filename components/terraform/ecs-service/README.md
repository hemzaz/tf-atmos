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
  the `services` layer of `workflows/deploy-full-stack.yaml`, after `ecs` (compute) and `alb`
  (addons).
- Consumers: `monitoring` reads `.service_name` (with the cluster's `.cluster_name`) for the
  `AWS/ECS` dimensions and `.target_group_arn_suffix` for `AWS/ApplicationELB` ones.
- `web-application/ecs-service` (`stacks/catalog/templates/web-application.yaml`) is the one
  instance: behind CloudFront through an internal ALB (a CloudFront VPC origin), its listener rule
  matches every path and the alb's default action is a fixed 403. `load_balancer.http_header`
  (a secret origin-verify header) is for an internet-facing ALB; the template does not use it.

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
- ECS Exec does not support a read-only root filesystem, so `exec_enabled` needs
  `readonly_root_filesystem = false` on every container (validated).
- ECS Exec session logging to CloudWatch Logs or S3 (the cluster's `execute_command_configuration`)
  needs extra task role permissions on that log group or bucket; they are not wired, since the
  `ecs` cluster sets no exec logging.
- Root filesystems are read-only by default (`readonly_root_filesystem`): a container that writes
  to local disk (`/tmp` included) needs `false`, since the component mounts no volumes.
- With `autoscaling` the service ignores `desired_count` after creation, and the service is a
  different resource: switching autoscaling on or off replaces the service (Cloud Posse's
  `ignore_changes_desired_count` pattern). The replacement's CreateService for the same name can
  fail while the old service is still draining. To switch in place, move the state first:
  `terraform state mv 'aws_ecs_service.this[0]' 'aws_ecs_service.autoscaled[0]'` when enabling
  autoscaling (the reverse when disabling), then apply. `alb_request_count_per_target` needs
  `load_balancer`.
- Every task definition change registers a new revision and rolls the service; the deployment
  circuit breaker (on, with rollback) returns to the last working revision if tasks fail.
- The target group name is `<Environment>-<name>` (32 characters at most). Changing its port,
  protocol or VPC replaces it, which fails while the listener rule still forwards to it: change
  the rule (or remove `load_balancer`) first.
- The listener rule's `priority` must be unique on the listener.
- `load_balancer.http_header` adds a header condition whose one value is read at plan from an SSM
  parameter (`data.aws_ssm_parameter`, decrypted): the planning role needs `ssm:GetParameter` on
  it and, for a SecureString on a customer managed key, `kms:Decrypt`. Keep it on the default
  `aws/ssm` key: `ReadOnlyAccess` (the CI plan role) grants `ssm:Get*`, and that key's policy
  admits the account's principals through SSM. The value is in plan and state
  (sensitive), as any listener rule condition is. It must be 16-128 letters, digits, `_` or `-`
  (ALB reads `*` and `?` as wildcards). After changing the parameter, apply this component and the
  `cloudfront` instance that sends the header: requests fail with the default action until both
  match.
- Part 2, not here: service connect and service discovery, blue-green deployments
  (`CODE_DEPLOY`), more than one target group, sidecars beyond the `containers` map
  (`dependsOn`, FireLens), and EFS or other volumes.
