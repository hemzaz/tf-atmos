# github-runners

Self-hosted GitHub Actions runners: an Auto Scaling group of EC2 instances in a stack's VPC. CI
uses them for what GitHub-hosted runners cannot reach, the clusters' private EKS API.

It is Cloud Posse `aws-github-runners` as plain resources, keeping its input names
(`github_scope`, `runner_labels`, `runner_version`, `min_size`/`max_size`, the userdata hooks). It
adds just-in-time (JIT) registration, which Cloud Posse's `philips-labs-github-runners` variant
uses. Cloud Posse's component reads a reusable registration token (or PAT) from
`ssm_path`/`ssm_path_key`, kept fresh by their token-rotator component. Neither those inputs nor
that component exist here, and `runner_group` (a name) became `runner_group_id`, which the JIT
API takes.

## How a runner starts

1. CI executes the group's `<name>-start` policy, a +1 that Auto Scaling caps at `max_size`
   (`min_size` 0). CI's roles can do nothing else to the group; scale-in never picks a runner
   (`protect_from_scale_in`).
2. The launch lifecycle hook holds the new instance (Pending:Wait).
3. EventBridge invokes the `jit` function (`functions/jit`, Node.js 22, no dependencies). It:
   - reads the GitHub App private key from SSM;
   - takes an installation token scoped to this repository and Administration write only;
   - calls `generate-jitconfig` for a runner named after the instance;
   - revokes the token;
   - writes the instance's lease, `<jit_parameter_prefix>/lease/<instance id>` (String, tagged
     with the instance's ARN);
   - writes the single-use configuration to `<jit_parameter_prefix>/<instance id>` (SecureString
     on `kms_key_arn`, tagged with the instance's ARN). The prefix defaults to
     `/github/runners/<name>/jit`, so two pools in one account never share a path or its grants;
   - completes the lifecycle action. On any failure it abandons the launch, so the instance is
     terminated.
4. The instance reads its configuration, deletes it, and runs `run.sh --jitconfig` for one job.
5. It leaves by deleting its own lease (an EXIT trap: after its job, after any bootstrap failure,
   and when it gets no job within `idle_timeout_seconds`). The deletion's EventBridge event
   ("Parameter Store Change", Delete) invokes the function, which ends that instance, lowering
   desired capacity, if it is an InService runner of this group.
6. On termination the function deletes an unread configuration, the lease and any runner
   registration left behind.

The instance role has no Auto Scaling action. Cloud Posse's `aws-github-runners` and
philips-labs' runners let the instance end itself (`TerminateInstanceInAutoScalingGroup` on the
instance role, or a scale-down Lambda); IAM cannot scope that call to the caller's own instance, so
a job could end a sibling runner. Here the only thing a runner can do is delete its own lease
(the parameter is tagged with its ARN; the role may delete only parameters tagged with
`ec2:SourceInstanceARN`), and the function ends exactly that instance.

A JIT configuration registers one ephemeral runner, once. A copy taken after its runner started
is useless, and no reusable registration credential exists anywhere.

## Wiring

- Catalog: `github-runners/defaults`, with one instance per workload-account VPC.
  - `vpc_id` and `subnet_ids` come from the vpc instance's private subnets, which need a NAT path
    to GitHub. They replace Cloud Posse's remote-state read.
  - `runner_labels` is the stack's full id, its name `<tenant>-<environment>-<stage>[-<name>]`
    (`{{ .atmos_stack }}`).
- Used by:
  - an eks instance admits `.security_group_id` in `allowed_security_group_ids`;
  - CI executes `.start_policy_name` for `runs-on: [self-hosted, <full id>]`
    jobs.

## One-time GitHub App setup (owner)

1. Create a GitHub App (Settings → Developer settings → GitHub Apps), with no webhook and no
   callback.
   - Repository permission: **Administration: Read and write**. That is the repository runner
     API; for organization runners use **Self-hosted runners: Read and write** instead.
   - **Metadata: Read** is implied.
   - No other permission.
2. Install it on this repository only. Set its App ID and installation ID (not secrets) as
   `github_app_id` and `github_app_installation_id`.
3. After the pool's first apply, generate a private key and store it with the pool's own key
   (`.app_key_kms_key_alias`) at `.app_private_key_parameter_name`. Then delete the downloaded
   file. The key never goes in the repository, a stack file or the state.

   ```bash
   aws ssm put-parameter --type SecureString --name /github/runners/github-runners/app-private-key \
     --key-id alias/<Environment>-github-runners-github-app --value file://app.private-key.pem
   ```

## Notes

- **The App key's own KMS key.** Its key policy lets the account administer it and encrypt with
  it, but only the `jit` function's role may decrypt, and only for that parameter through SSM.
  There is no IAM delegation for Decrypt, so no other role can read the key unless it holds
  `kms:PutKeyPolicy` or `kms:CreateGrant` on that key (the account keeps PutKeyPolicy, so the key
  stays recoverable; it gets no CreateGrant).
- **The instance role reaches nothing of value.**
  - It may read and delete only its own JIT parameter and lease (`aws:ResourceTag/RunnerInstanceArn`
    against `ec2:SourceInstanceARN`). An explicit deny covers reading any other parameter.
  - It has no Auto Scaling action: it leaves through its lease, so a job cannot end another
    runner of the pool.
  - It has minimal Session Manager actions instead of `AmazonSSMManagedInstanceCore` (which allows
    `ssm:GetParameter*` on `*`).
  - Terraform jobs get AWS access from GitHub OIDC (the stack's `iam/ci` roles), not from the
    instance.
- **The docker group is root-equivalent.** Jobs run as the unprivileged `runner` user, which is in
  the `docker` group so container jobs (the atmos image) start. That is acceptable only because
  the instance runs a single job and its role reaches nothing of value.
- **The JIT configuration is in `run.sh`'s argv**, visible to the job. It is single-use, so a
  copy is worthless once the runner has started.
- **Failures.** A failed launch terminates the instance with a lower desired capacity (no
  launch loop) and abandons the lifecycle action. If Auto Scaling refuses to terminate an
  instance still in Pending:Wait, the function lets the launch continue instead: the instance
  finds no JIT configuration and its EXIT trap terminates it, decrementing, from InService.
  Either way the function fails, which `<name>-jit-errors` alarms on
  (`alarm_sns_topic_arns`). EventBridge's invoke is not retried (`maximum_retry_attempts` 0): a
  retry would mint a second configuration. A runner whose bootstrap fails before it knows its
  instance id can only power off, which the group replaces.
- **The lease event is best effort.** EventBridge may drop or delay the deletion's event, the
  delete itself may fail, or Auto Scaling may refuse the terminate. Three bounds, cheapest first:
  - the function retries Throttling, ResourceContention and ScalingActivityInProgress after 5, 10
    and 20 s (the InService check keeps it idempotent);
  - every 15 minutes (`<name>-sweep`) the function ends, lowering capacity, each InService runner
    of this group launched over 10 minutes ago that has no lease;
  - the runner powers off 600 s after deleting its lease (`instance_initiated_shutdown_behavior`
    terminate): the group replaces it with a runner that, finding no job, idles out after
    `idle_timeout_seconds` and leaves through its lease.

  The lease is written first at launch, before anything that can fail, so even a launch that
  fails and continues boots with one: no instance can only power off into a replacement loop.
- **A pinned runner release.** `runner_version` with `runner_sha256` (the release notes'
  linux-x64 SHA) replaces Cloud Posse's latest release. Bump both before GitHub stops accepting
  the release.
- **Instance hardening.** Amazon Linux 2023, IMDSv2 only with hop limit 1, no public IP, an
  egress-only security group (`name_prefix`, `create_before_destroy`), and a gp3 root volume on
  `kms_key_arn` (`kms/main` grants the Auto Scaling service-linked role, `allow_autoscaling_ebs`).
- **No `instance_refresh`.** It would end running jobs. `max_instance_lifetime` (one day) is the
  backstop.
- **Public repository: the fork guard is on the runner.** Self-hosted runners on a public
  repository must never run fork code, and workflow files are pull-request controlled (a fork
  can ask for `runs-on: [self-hosted, <label>]` and drop `container:`). So every runner's
  job-started hook (`files/job-started.sh`, set by the bootstrap in the runner's `.env`) fails a
  job before its first step unless:
  - `GITHUB_REPOSITORY` is `github_scope` (or one of its repositories, for an organization);
  - the event is `push`, `workflow_dispatch`, `schedule` or `merge_group`, or `pull_request`
    whose head repository (`.pull_request.head.repo.full_name` in the event payload) is that
    repository. `pull_request_target`, `workflow_run`, `issue_comment` and any other event are
    refused;
  - with `allowed_refs` (every pool in this repository: `[refs/heads/master]`, from the catalog),
    `GITHUB_REF` is one of them.

  `GITHUB_*` and the payload come from GitHub; the hook and its policy are root-owned.
  `test_runner_scripts.py` runs the hook for fork, `pull_request_target` and same-repository
  events. The owner also keeps Settings → Actions → General → "Require approval for all outside
  collaborators" on.
- **A refused job does not cost a runner.** The hook's refusal leaves a marker
  (`/var/lib/runner-state/refused`, owned by the runner user). The EXIT trap then powers the
  instance off with its lease kept, without lowering desired capacity, so the group launches a
  replacement that takes the next queued job. Queueing jobs for a label (say production's) cannot
  starve the master job the runner was started for. There is no loop: each replacement consumes
  one refused job, and an idle replacement leaves through its lease, lowering capacity. A job the
  hook admitted can write the marker too (it runs as the same `runner` user): that costs one idle
  runner per such job, which the job queue bounds, and grants nothing.
- The `jit` function's flow is tested with `node --test functions/jit/`.
