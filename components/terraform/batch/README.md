# batch

AWS Batch managed compute environments (`EC2`, `SPOT`, `FARGATE`, `FARGATE_SPOT`) and the job
queues that feed them, one map entry each, named `<Environment>-<name>-<key>`. Cloud Posse has no
Batch component, so the shape follows this repo's map-based components. Job definitions are not
in this component yet.

## Wiring

- No instance in the fnx stacks. `batch/defaults` is the abstract base; an instance sets
  `subnet_ids` and `security_group_ids` per compute environment (from `vpc/main` and a
  `securitygroup` instance, both listed in `dependencies.components`). It deploys in the
  `compute` layer of `workflows/deploy-full-stack.yaml`, after networking and connectivity.
- `job_queues.*.compute_environment_order` names `compute_environments` keys of the same instance,
  or a compute environment ARN from elsewhere.
- Consumers (Step Functions `batch:submitJob`, EventBridge targets, job submitters) read
  `.job_queue_arns.<key>`; CloudWatch dimensions read `.compute_environment_names` and
  `.job_queue_names`.
- `stacks/catalog/templates/batch-processing.yaml` predates this component and still uses the
  old split `batch`/`batch-job-queue`/`batch-job-definition` inputs; it needs porting.

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
  `SPOT_PRICE_CAPACITY_OPTIMIZED` uses EC2 Fleet through the service-linked role.
- `BEST_FIT` environments cannot take infrastructure updates (`update_policy` is rejected), so
  AMI, instance type or launch template changes replace them.
- A queue cannot mix Fargate and EC2/SPOT environments, takes at most 3, and cannot switch
  between FIFO and `fair_share_policy` in place.
- The component creates no security groups; ingress rules belong to the `securitygroup` instance
  it is given (jobs need no inbound access).
- Replacing a compute environment fails while a queue still references it: change the queue's
  order first, or replace both together.
