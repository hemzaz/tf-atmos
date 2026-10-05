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

1. CI raises the group's desired capacity (`min_size` 0).
2. The launch lifecycle hook holds the new instance (Pending:Wait).
3. EventBridge invokes the `jit` function (`functions/jit`, Node.js 22, no dependencies). It:
   - reads the GitHub App private key from SSM;
   - takes an installation token scoped to this repository and Administration write only;
   - calls `generate-jitconfig` for a runner named after the instance;
   - revokes the token;
   - writes the single-use configuration to `<jit_parameter_prefix>/<instance id>` (SecureString
     on `kms_key_arn`, tagged with the instance's ARN);
   - completes the lifecycle action. On any failure it abandons the launch, so the instance is
     terminated.
4. The instance reads its configuration, deletes it, and runs `run.sh --jitconfig` for one job.
5. It leaves the group, lowering desired capacity. An EXIT trap does this after any bootstrap
   failure, too. An instance that gets no job within `idle_timeout_seconds` leaves as well.
6. On termination the function deletes an unread configuration and any runner registration left
   behind.

A JIT configuration registers one ephemeral runner, once. A copy taken after its runner started
is useless, and no reusable registration credential exists anywhere.

## Wiring

- Catalog: `github-runners/defaults`, with one instance per workload-account VPC.
  - `vpc_id` and `subnet_ids` come from the vpc instance's private subnets, which need a NAT path
    to GitHub. They replace Cloud Posse's remote-state read.
  - `runner_labels` is the stack's full id `<tenant>-<environment>-<stage>`, built from context.
- Used by:
  - an eks instance admits `.security_group_id` in `allowed_security_group_ids`;
  - CI raises `.autoscaling_group_name`'s desired capacity for `runs-on: [self-hosted, <full id>]`
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
  There is no IAM delegation for Decrypt, so no other role can read the key, whatever its IAM
  policy says.
- **The instance role reaches nothing of value.**
  - It may read and delete only its own JIT parameter (`aws:ResourceTag/RunnerInstanceArn` against
    `ec2:SourceInstanceARN`). An explicit deny covers every other parameter.
  - It may leave its own group.
  - It has minimal Session Manager actions instead of `AmazonSSMManagedInstanceCore` (which allows
    `ssm:GetParameter*` on `*`).
  - Terraform jobs get AWS access from GitHub OIDC (the stack's `iam/ci` roles), not from the
    instance.
  - IAM has no key for the instance an Auto Scaling call targets, so "leave the group" is scoped
    to the group: a job could end a sibling runner of the same pool, and nothing else.
- **The docker group is root-equivalent.** Jobs run as the unprivileged `runner` user, which is in
  the `docker` group so container jobs (the atmos image) start. That is acceptable only because
  the instance runs a single job and its role reaches nothing of value.
- **A pinned runner release.** `runner_version` with `runner_sha256` (the release notes'
  linux-x64 SHA) replaces Cloud Posse's latest release. Bump both before GitHub stops accepting
  the release.
- **Instance hardening.** Amazon Linux 2023, IMDSv2 only with hop limit 1, no public IP, an
  egress-only security group (`name_prefix`, `create_before_destroy`), and a gp3 root volume on
  `kms_key_arn` (`kms/main` grants the Auto Scaling service-linked role, `allow_autoscaling_ebs`).
- **No `instance_refresh`.** It would end running jobs. `max_instance_lifetime` (one day) is the
  backstop.
- **Public repository.** Self-hosted runners on a public repository must never run fork code.
  - CI's self-hosted jobs run only on push to master, `workflow_dispatch`, `merge_group`,
    schedule, and same-repository pull requests.
  - The owner must also turn on Settings → Actions → General → "Require approval for all
    outside collaborators".
- The `jit` function's flow is tested with `node --test functions/jit/`.
