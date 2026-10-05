# github-runners

Self-hosted GitHub Actions runners: an Auto Scaling group of EC2 instances in a stack's VPC. CI
uses them for what GitHub-hosted runners cannot reach, the clusters' private EKS API. This is
Cloud Posse `aws-github-runners` as plain resources, keeping its input names (`github_scope`,
`runner_labels`, `runner_group`, `runner_version`, `min_size`/`max_size`, the userdata hooks).

## Wiring

- Catalog: `github-runners/defaults`, with one instance per workload-account VPC.
  - `vpc_id` and `subnet_ids` come from the vpc instance's private subnets (which have a NAT path
    to GitHub). They replace Cloud Posse's remote-state read.
  - `runner_labels` is the stack's full id `<tenant>-<environment>-<stage>`, built from context.
  - `registration_token_parameter_name` is `github-action-token-rotator`'s `.token_parameter_name`.
- Used by:
  - an eks instance admits `.security_group_id` in `allowed_security_group_ids`;
  - CI raises the group's desired capacity (`.autoscaling_group_name`) to start runners for
    `runs-on: [self-hosted, <full id>]` jobs.

## Notes

- **Ephemeral by default.** Each instance registers with `--ephemeral`, takes one job, then leaves
  its group and lowers desired capacity. With `min_size` 0, nothing runs until CI asks. An
  instance that gets no job within `idle_timeout_seconds` leaves too, and GitHub deletes its
  offline registration. `max_instance_lifetime` (one day) is the backstop. Because runners leave
  on their own, this component has no CPU scaling policies, no graceful scale-in hook, and no
  `instance_refresh` (which would kill running jobs). `ephemeral = false` keeps Cloud Posse's
  long-lived runner service.
- **The runner release is pinned and checked.** `runner_version` plus `runner_sha256` (the release
  notes' linux-x64 SHA) replace Cloud Posse's download of the latest release. The runner does not
  update itself, so bump both before GitHub stops accepting the release.
- **The instance role is minimal.** It can read and decrypt the token (through SSM only), leave
  its own group, and use Session Manager. Terraform jobs get AWS access from GitHub OIDC into the
  stack's `iam/ci` roles, not from the instance. So there are no ECR or cross-account grants, as
  Cloud Posse's role has.
- **Instance hardening.** IMDSv2 only, hop limit 1, no public IP, an egress-only security group,
  and a gp3 root volume encrypted with `kms_key_arn`. Jobs run as the unprivileged `runner` user,
  which is in the `docker` group so container jobs (the atmos image) start. That group is
  root-equivalent on the instance, which is acceptable for an instance used for a single job.
- **Public repository.** Self-hosted runners on a public repository must never run fork code.
  - CI's self-hosted jobs run only on push to master, `workflow_dispatch`, `merge_group`,
    schedule, and same-repository pull requests.
  - The owner must also turn on Settings → Actions → General → "Require approval for all
    outside collaborators".
