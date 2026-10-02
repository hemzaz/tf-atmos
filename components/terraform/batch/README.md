# batch

AWS Batch managed compute environments (`EC2`, `SPOT`, `FARGATE`, `FARGATE_SPOT`), the job
queues that feed them and container job definitions, one map entry each, named
`<Environment>-<name>-<key>`. Job definitions come with their log group
(`/aws/batch/<Environment>-<name>`, KMS-encrypted), a shared execution role and optional per-job
roles. Cloud Posse has no Batch component, so the shape follows this repo's map-based components;
the roles follow its ecs-service pattern (created unless an ARN is given).

## Wiring

- No instance in the fnx stacks. `batch/defaults` is the abstract base; an instance sets
  `subnet_ids` and `security_group_ids` per compute environment (from `vpc/main` and a
  `securitygroup` instance, both listed in `dependencies.components`). It deploys in the
  `compute` layer of `workflows/deploy-full-stack.yaml`, after networking and connectivity.
- `job_queues.*.compute_environment_order` names `compute_environments` keys of the same instance,
  or a compute environment ARN from elsewhere.
- Consumers (Step Functions `batch:submitJob`, EventBridge targets, job submitters) read
  `.job_queue_arns.<key>` and `.job_definition_names.<key>` (or `.job_definition_arn_prefixes`);
  CloudWatch dimensions read `.compute_environment_names` and `.job_queue_names`. IAM for
  submitters scopes `batch:SubmitJob` to the queue ARN and `<job_definition_arn_prefix>:*`.
- `events_role_enabled` creates `<Environment>-<name>-events` (`events_role_arn`), the `role_arn`
  an `eventbridge` Batch job queue target needs; it may only submit this instance's definitions to
  its queues. The `eventbridge` component creates no target roles.
- `job_definitions` need `log_kms_key_arn` (`!terraform.state kms/main .key_arn`, with `kms/main`
  in `dependencies.components`); its key policy must allow CloudWatch Logs
  (`allow_cloudwatch_logs`, on in `catalog/kms/defaults`).
- `secrets` take Secrets Manager secret ARNs (full, with the 6-character suffix; e.g. a
  `secretsmanager` instance's output) or SSM parameter ARNs; set `secrets_kms_key_arn` when they
  are encrypted with a customer managed key.
- The `batch-processing` catalog template runs one instance, `batch-processing/batch`, read by
  its state machines, EventBridge rules and monitoring.

## Notes

- No service role: Batch uses the `AWSServiceRoleForBatch` service-linked role, which it creates
  on first use (the deployer needs `iam:CreateServiceLinkedRole`).
- EC2/SPOT environments share one `<Environment>-<name>-instance` role and profile with only
  `AmazonEC2ContainerServiceforEC2Role`, unless they set `instance_role`. Jobs get AWS access from
  their job role, not this one.
- Each EC2/SPOT environment gets a launch template requiring IMDSv2 with hop limit 1, so
  bridge-networked job containers cannot reach the instance credentials. Raise the hop limit only
  for jobs that must read IMDS.
- `spot_iam_fleet_role` is only needed for `SPOT` with `BEST_FIT`; the default
  `SPOT_PRICE_CAPACITY_OPTIMIZED` uses EC2 Fleet through the service-linked role. That fleet role
  needs `AmazonEC2SpotFleetTaggingRole` (not the older `AmazonEC2SpotFleetRole`) for the Spot
  instances to be tagged.
- EC2/SPOT instance tags include the stack's `tags`, so changing any of them (org-wide ones
  included) is an infrastructure update of every EC2/SPOT environment; on `BEST_FIT` it replaces
  the environment, which fails while a queue references it (below).
- `instance_role` must be an instance profile ARN; a name or a role ARN is rejected.
- Leave `desired_vcpus` unset: Batch rescales it, so a set value drifts on every plan.
- `BEST_FIT` environments cannot take infrastructure updates (`update_policy` is rejected), so
  AMI, instance type or launch template changes replace them.
- A queue cannot mix Fargate and EC2/SPOT environments, takes at most 3, and cannot switch
  between FIFO and `fair_share_policy` in place.
- The component creates no security groups; ingress rules belong to the `securitygroup` instance
  it is given (jobs need no inbound access).
- Replacing a compute environment fails while a queue still references it: change the queue's
  order first, or replace both together.

### Job definitions

- Every change registers a new revision and deregisters the previous one, so
  `.job_definition_arns` (revisioned) changes on every edit and a consumer holding the old ARN
  submits to an inactive revision until it is re-applied. Step Functions, EventBridge targets and
  submitters should use `.job_definition_names` or `.job_definition_arn_prefixes`, which
  `SubmitJob` resolves to the latest active revision; use `.job_definition_arns` only to pin one.
- The execution role (`<Environment>-<name>-job-execution`, or `execution_role_arn`) is used by
  `FARGATE` definitions and by any definition with `secrets`. It can create streams in the
  component log group, read exactly the definitions' secrets (Secrets Manager secret ARNs without
  the json-key tail, SSM parameter ARNs, `kms:Decrypt` on `secrets_kms_key_arn` through those two
  services) and, for Fargate, pull images: `ecr_repository_arns`, or every repository when empty
  (as `AmazonECSTaskExecutionRolePolicy`). `EC2` definitions without secrets pull and log with
  the instance role.
- A job role is created (`<Environment>-<name>-<key>-job`) only for definitions with
  `job_role_policy_arns` or `job_role_policy_json`; `job_role_arn` uses an existing one. Without
  either the job has no AWS credentials.
- Both roles trust `ecs-tasks.amazonaws.com` with `aws:SourceAccount` = this account. Job roles
  also require `aws:SourceArn` like `arn:aws:ecs:<region>:<account>:*` (AWS's confused-deputy
  guidance for task roles; a cluster-specific ARN is not supported). The execution role does not:
  the ECS and Batch execution role docs show no `SourceArn`, and one the agent does not send
  would fail every job using the role at start. A role given by ARN needs a trust that allows ECS
  tasks.
- Definitions log with `awslogs` to the component log group, stream prefix = the key (or
  `log_stream_prefix`). Another log group would not be covered by the created execution role.
- Fargate takes only the documented vCPU/memory pairs (0.25-16 vCPU), no `privileged`, `gpu`,
  `ulimits`, shared memory or devices; `assign_public_ip` defaults to `DISABLED`, so the subnets
  need a NAT gateway or VPC endpoints (ECR, S3, Logs, Secrets Manager/SSM) to pull and log. EC2
  definitions take whole vCPUs and reject the Fargate-only settings.
- `cpu_architecture = "ARM64"` needs `FARGATE` compute environments: Fargate Spot does not
  support ARM64, so such a job on a `FARGATE_SPOT` queue never starts.
- `secrets` take full Secrets Manager ARNs with the 6-character suffix (the IAM grant is the exact
  ARN, which a suffix-less partial ARN would not match).
- Root filesystems are read-only by default (`readonly_root_filesystem`): a job that writes to
  local disk (`/tmp` included) needs `false`, since the component mounts no volumes.
- `scheduling_priority` only takes effect on a fair-share queue.
