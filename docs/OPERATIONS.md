# Operations

Bootstrap, deploy and run the stacks; the developer side is in the [README](../README.md).
Workflows shown with `-s <stack>` take the flag; those shown with `STACK=<stack>` read the
variable (or prompt).

## First-deploy inputs

The stacks hold placeholders. Replace them before any apply against a real account.

| Input | Where |
|-------|-------|
| Account IDs | `settings.account_map.full_account_map` in `stacks/orgs/fnx/_defaults.yaml`, the only place: `root` (management), `dev`, `staging`, `prod`. Each stage's `settings.environment.account_id`, `management_account_id`, the backend `access_roles` ARNs in `fnx-ue1-root` and every provider's `allowed_account_ids` are read from it, so that guard fails every real plan and apply until the map holds the real IDs. `scripts/new-environment.sh` adds a new account here (`AWS_ACCOUNT_ID`). The emulator and fixture stacks keep the emulator's `000000000000` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` |
| Cross-account role callers | `trusted_principal_arns` in `stacks/catalog/iam/defaults.yaml`: the management-account role ARNs (path included) allowed to assume each workload account's `-CrossAccountRole`. The placeholder `<tenant>-cross-account-operator` matches nobody until it exists |
| Cognito feature plan | `user_pool_tier: PLUS` with `advanced_security_mode: ENFORCED` in `stacks/catalog/cognito/defaults.yaml`: PLUS is billed from the first monthly active user. `OFF` + `ESSENTIALS` per instance is the cheaper choice |
| Domains | `settings.environment.domain_name` in each stack's `components/globals.yaml`; every zone, record, certificate and API domain derives from it |
| Alert recipients | `alarm_email_subscriptions` on monitoring instances and the lists in `components/globals.yaml`; each address must confirm its SNS subscription |
| Prod RDS alarm target | `sns_topic_arn` on prod's `rds/main`: unset, so its CloudWatch alarms have no action |
| Lambda packages | the application repo that builds them, as `lambda_uploader_trusted_github_repos` on each stack's `iam/ci` (`components/security.yaml`), then a first upload per function: see [Lambda packages](#lambda-packages). Until then every `lambda/*` instance is `metadata.enabled: false` |
| GitHub | default-branch protection, applied: PR required, linear history, no force-push, required check `CI gate` (the `terraform-ci.yml` job that reports on every PR and fails if any CI job failed). No tag ruleset guards `refs/tags/deployed/**`: on a personal repo GitHub Actions cannot be a ruleset bypass actor, and a ruleset without that bypass blocks `terraform-cd.yml`'s own tag moves. Add it once the repo moves to an organization |
| GitHub App | the self-hosted CI runners' just-in-time registration: a GitHub App installed on this repository (Administration read/write); its IDs in `settings.github_app` (`app_id`, `installation_id`; `0` until set) in `stacks/orgs/fnx/_defaults.yaml`; and, after each runner pool's first apply, its private key in that account's SSM at the pool's `.app_private_key_parameter_name`, encrypted with the pool's own key (`.app_key_kms_key_alias`): see `components/terraform/github-runners/README.md`. The repository is public: turn on Settings → Actions → General → "Require approval for all outside collaborators" |
| Deploy tags | one `deployed/<stack>` tag per stack: `git tag deployed/<stack> <sha> && git push origin deployed/<stack>` |
| EKS cluster admins | `map_additional_iam_roles` in each stack's `components/globals.yaml`: see [In-cluster components](#in-cluster-components). While empty, nobody can apply the in-cluster components |

Every workload `account_id` must differ from `management_account_id`. The stage split of state
access below holds only then: a workload stack in the management account puts its
`AdministratorAccess` apply role in the bucket's own account, where it reads and writes every
stage's state without going through the access roles.

**Preflight.** Run it before the first deploy, and again once the inputs are filled in:

```bash
atmos describe stacks --process-functions=false --format json \
  | python3 workflows/scripts/common/check-first-deploy-inputs.py [--stacks <stack>,...]
```

It reads the resolved stacks, so it checks each value wherever it is written. It fails on each of
the following, naming the stack, the key and the row above:

- a placeholder account ID (`123456789012`, `000000000000`), ARNs included;
- `o-xxxxxxxxxx`;
- an `example.com`/`.test` domain or alert address;
- an empty EKS admin role list;
- an unset prod RDS alarm target;
- a placeholder (`0`) GitHub App ID or installation ID;
- a workload account equal to the management account;
- two stages sharing one account.

It prints the rows no file can settle (Cognito plan, the operator role's existence, Lambda
packages, GitHub, deploy tags, the GitHub App's key and outside-collaborator approval) as notices. The `local` and `fixtures` stacks are exempt.
`bootstrap.yaml` runs it fatally for the stack being deployed (`backend-cold-start`,
`backend-only`, `full`) before any AWS call. `atmos workflow lint` runs it with `--warn`: it
never fails, and prints the counts per row plus the first 10 findings (`--warn --all` prints
them all). It stands in for Cloud Posse's cold-start checks: there, `account-map` holds the
account IDs and the accounts layer is deployed and verified first
([deploy accounts](https://docs.cloudposse.com/layers/accounts/deploy-accounts/),
[aws-account-map](https://github.com/cloudposse-terraform-components/aws-account-map)).

## State backend

One bucket, `fnx-terraform-state`, in the management account, with native S3 lockfiles
(`use_lockfile: true`, no DynamoDB). It is `backend/main` in `fnx-ue1-root`, and every stack's
backend (`stacks/orgs/fnx/_defaults.yaml`) assumes one of its access roles, so it is created first,
with management-account administrator credentials. The bucket lives in one region,
`settings.tfstate.region` (`us-east-1`), and every stack's backend uses it whatever the stack's own
region is, so a DR or EU stack keeps its state here too. S3 replicates it to
`fnx-terraform-state-replica` in `settings.tfstate.replica_region` (`us-east-2`), encrypted with
the state key's multi-region replica (`backend/main`'s `s3_replication_enabled`; see
[State during a us-east-1 outage](#state-during-a-us-east-1-outage)):

```bash
atmos workflow backend-cold-start -f bootstrap   # once: apply with local state, then migrate it into the bucket
atmos workflow backend-only -f bootstrap         # later backend changes
atmos workflow verify -f bootstrap               # backend describe + outputs
```

An existing bucket must be imported first: see `components/terraform/backend/README.md`.

Every role also trusts the administrator who applied `backend/main`; the stack backend picks the
role from the stack's stage and `TFSTATE_ACCESS`, whoever runs it.

| Role (`access_roles` key) | Access | Trusted CI role |
|---------------------------|--------|-----------------|
| `fnx-terraform-backend-read-role` (`read`) | read, dev/staging state | dev/staging CI plan roles |
| `fnx-terraform-backend-role` (`write`) | read/write, dev/staging state | dev/staging CI apply roles |
| `fnx-terraform-backend-prod-read-role` (`prod_read`) | read, prod state (`fnx-ue1-prod`, DR `fnx-ue2-prod`) | the prod stacks' CI plan roles |
| `fnx-terraform-backend-prod-role` (`prod_write`) | read/write, prod state | the prod stacks' CI apply roles |
| `fnx-terraform-backend-root-role` (`root_write`) | read/write, `fnx-ue1-root` state | none |

- CI plans set `TFSTATE_ACCESS=read` and plan with `-lock=false`; deploys leave it unset.
- Trust is by role ARN, listed in `access_roles` in `stacks/orgs/fnx/root/us-east-1.yaml`. Add a new stack's
  `<tenant>-<environment>-<stage>-ci-plan`/`-apply` roles there (iam/ci's `ci_role_name_prefix`),
  and any operator role that runs Terraform against a stage. `check-ci-state-roles.py` (in `lint`
  and `validate-all`) fails a CI role its stage's read or write role does not trust.
- Each stack's state is an exact pattern pair on its stage's roles, `*/<stack>/*` and
  `*/<stack>-*` (`stacks/orgs/fnx/root/us-east-1.yaml`): add a new stack's pair before its first
  `init`. `check-state-keys.py` (in `lint` and `validate-all`) evaluates those patterns against
  every state key, requiring exactly its stage's roles to match it, and every backend region
  equal to `backend/main`'s.
  `s3:ListBucket` is bucket-wide, so every role sees key names across stages, never contents.
- The CI apply role (`iam/ci`, `AdministratorAccess`) trusts only the default-branch subject
  (`repo:<org>/<repo>:ref:refs/heads/<default branch>`). `terraform-cd.yml` uses no GitHub
  Environment: **every merge deploys, prod included, with no manual approval**. Default-branch
  protection is the gate. PR code gets only the dev/staging plan roles; prod is planned on push
  to master (`pull_request_plans_enabled: false` in `stacks/orgs/fnx/prod/_defaults.yaml`).

### State during a us-east-1 outage

The replica is read-only for every access role, write roles included: they may list it and read
their own stage's objects, never write, delete or lock. Its bucket policy also denies object
writes and deletes to every principal but the replication role. Point a run at it with
`TFSTATE_SOURCE=replica` (`stacks/orgs/fnx/_defaults.yaml` then renders bucket
`fnx-terraform-state-replica`, region us-east-2). Leave `TFSTATE_ACCESS` unset: the stage's usual
read/write role, the one operators and the CI apply roles assume, is read-only on the replica. The
read roles trust only the CI plan roles.

```bash
export TFSTATE_SOURCE=replica
atmos terraform init vpc/main -s fnx-ue2-prod -- -reconfigure       # the replica's backend
atmos terraform plan vpc/main -s fnx-ue2-prod -- -lock=false        # read-only: plan, output, show
atmos terraform output rds/main -s fnx-ue1-prod
```

What is safe and what is not:

- Safe: `plan -lock=false`, `output`, `show`, `state list`/`state pull`, and `!terraform.state`
  reads (`atmos describe component` with functions) for any stack.
- Not possible, by design: `apply`, `import`, `state push`/`rm`/`mv`, or a plan that takes a lock.
  The roles cannot write the replica, so the S3 backend fails on the `.tflock` it cannot create.
  An apply against a copy while the primary may come back would fork the state: the two buckets
  would disagree once us-east-1 returns, and replication would overwrite the replica's side.
- Lock files replicate like state. A `.tflock` copied while a run held the lock in us-east-1 may
  sit in the replica; `-lock=false` ignores it. Do not `force-unlock` against the replica.
- Replication is asynchronous (typically seconds; S3 gives no bound without Replication Time
  Control): the replica may miss the last writes before the outage.
- A component that has never been applied has no state to fork. One that must be applied during the
  outage (the DR stack's `eks-backend-services/main`) may apply with local state and be migrated
  into the bucket when it returns, the way the backend's own cold start does (`bootstrap.yaml`).
  Keep `TFSTATE_SOURCE=replica` exported for that deploy: its `!terraform.state` inputs then read
  the replica, while its own state stays local (no generated backend file):

  ```bash
  export TFSTATE_SOURCE=replica
  rm -f components/terraform/eks-backend-services/backend.tf.json   # no S3 backend: local state
  atmos terraform deploy eks-backend-services/main -s fnx-ue2-prod --auto-generate-backend-file=false
  # later, with the bucket back:
  unset TFSTATE_SOURCE
  atmos terraform init eks-backend-services/main -s fnx-ue2-prod --init-reconfigure=never -- -migrate-state -force-copy
  ```

  Keep the local `terraform.tfstate.d/` until the migration has run.
- The replica holds the state as of the outage. A component that the outage runbook changed by CLI
  (a promoted database, a moved cache primary) still shows its pre-outage outputs there, so an
  input read from it may be stale or null: set such an input literally, from the CLI's answer, on
  the branch that deploys.

- After the outage: unset `TFSTATE_SOURCE` and `init -reconfigure` again before any apply.
  Nothing is copied back: the primary bucket never stopped being the source of truth.

`dr-status` reports whether the bucket replicates and to where.

## Repository variables

| Variable | Value |
|----------|-------|
| `AWS_PLAN_ROLE_ARN` | the "AWS is configured" switch: unset = AWS jobs skip. Any non-empty value enables them (by convention a `ci_plan_role_arn`); no job assumes it |
| `AWS_REGION` | optional override (default `us-east-1`) |

No role ARN is a variable. Every AWS job assumes its stack's own `iam/ci` role, in that stack's
account, derived by `workflows/scripts/common/ci-apply-role-arn.py` as
`arn:aws:iam::<settings.environment.account_id>:role/<ci_role_name_prefix>-<kind>`: `--kind plan`
for PR/master plans, drift and DR checks; `--kind apply` (default) for CD. This is Cloud Posse's
per-account planner/terraform role pair (`github-oidc-role`). `settings.environment.account_id`
already comes from the account map (Account IDs, above), so a new or changed account needs no
script change. `AWS_PROD_PLAN_ROLE_ARN` is gone; delete it from the repository.
For CI across several accounts from one OIDC provider, see
[examples/github-oidc-hub-spoke](../examples/github-oidc-hub-spoke/README.md).

## Deploying a stack

After the backend: `atmos workflow full -f bootstrap -s <stack>` (IAM, including the CI roles, and
VPCs) with administrator credentials in the stack's account, since no CI role exists yet; no
stack sets a provider role, so every component runs as the caller. Then
`atmos workflow deploy -f deploy-full-stack -s <stack>`. It runs these layers in order, each
planned, confirmed, then applied from the saved plan. Each layer is also its own workflow
(`atmos workflow deploy-<layer> -f deploy-full-stack -s <stack>`):

`backend`, `iam`, `kms`, `storage`, `networking`, `connectivity`, `security`,
`security-monitoring`, `compute`, `platform`, `data`, `dns-zones`, `dns`, `certificates`,
`addons`, `services`, `regional-waf`, `monitoring`.

The selection of each layer is in `workflows/deploy-full-stack.yaml`. An instance that reads
another's state must be in a later layer; `check-deploy-layers.py` (validate-all) enforces that
and that every enabled instance is in exactly one layer.

**Before `certificates`: delegate the stack's domain.** ACM validates in `network/main`'s `main`
zone, so its domain must resolve, or validation times out after 45 minutes. Prod's
`fnx.example.com` is delegated at the registrar to prod's `zone_name_servers.main`
(`atmos terraform output network/main -s fnx-ue1-prod`). Dev's and staging's parent is
that Terraform-managed zone: add an NS record for `dev.`/`staging.fnx.example.com` to prod's
`network/main` `records` (`stacks/orgs/fnx/prod/us-east-1/components/networking.yaml`)
with the child stack's `zone_name_servers.main`, and deploy prod's `network/main`.
`services.<d>` delegation is wired by the stacks themselves.

Other paths, once the instances they read have state:

```bash
atmos terraform deploy <component> -s <stack>                # one instance: plan + apply
atmos workflow apply -f apply-environment -s <stack>         # whole stack, one confirmation (not a first deploy)
atmos workflow deploy-app -f deploy-application -s <stack>   # secrets, Cognito, Lambda, ECS, API Gateway, monitoring
atmos workflow hot-deploy -f deploy-application -s <stack>   # Cognito, Lambda, API Gateway; no plan review
atmos workflow deploy -f deploy-template -s <stack>          # a stack template (stacks/catalog/templates/)
```

Template readiness follows `KNOWN_BROKEN_FIXTURES` in `workflows/scripts/common/fixtures.py`
(see [Template fixtures](#template-fixtures)): every template (`batch-processing`, `data-pipeline`,
`idp-platform`, `microservices-platform`, `serverless-api`, `web-application`) passes every check.

## In-cluster components

`eks-addons`, `external-secrets`, `eks-backend-services` and `alb-controller-ingress-group` talk to
the EKS API through the `kubernetes`/`helm` providers. Every cluster's endpoint is private
(`eks_public_access: false`), so GitHub-hosted runners cannot reach it. Their catalog defaults set
`settings.github.runner: in-vpc`, so CI runs them on the stack's self-hosted runners in the VPC
(`components/terraform/github-runners`):

- `.github/workflows/in-vpc.yml` is called once per (stack, runner label) for the plan on push to
  master (`terraform-ci.yml`), CD and dispatch (`terraform-cd.yml`, after the stack's hosted
  instances; `deployed/<stack>` moves only when both parts succeeded) and drift detection.
- **Master only, apply role only** (owner decision): these plans refresh Helm releases, whose
  state is in cluster Secrets, and the plan role (AmazonEKSViewPolicy, no Secrets) trusts pull
  requests. So every in-VPC job runs on the default branch with the stack's CI apply role, which
  trusts only master and is the cluster admin. A pull request that changes an in-cluster
  component gets a `::notice::` (no in-VPC plan). On master they are planned by the push plan
  (prod, like every prod plan), deployed by CD (whose log shows the plan it applies), and checked
  by drift detection; `workflow_dispatch` plans any stack's.
- Its first job starts one runner in the label's pool by executing the pool's +1 start policy
  (`atmos workflow start-runner -f ci-runners`; only the apply role may, on its stack's pools,
  `iam/ci` `ci_runner_pool_names`). Its second job runs on the ephemeral runner that starts.
- The label is the stack's full id (its name, `{{ .atmos_stack }}`), or
  `settings.github.runner_label`. The `microservices-platform` template runs its own pool in its
  own VPC.
- The repository is public. The workflow skips these jobs for a fork's pull request, but a
  pull request controls workflow files, so the guard is on the runner: every pool's job-started
  hook fails, before its first step, any job that is not this repository's push,
  `workflow_dispatch`, schedule, `merge_group` or same-repository pull request (github-runners
  README, "Public repository"). Keep "Require approval for all outside collaborators" on
  (First-deploy inputs, GitHub App).
- Production is reached from master only. Its CI roles trust only master's OIDC subject, so a
  pull request cannot start a prod runner, and its pool sets `allowed_refs: [refs/heads/master]`:
  the runner's job-started hook fails any other ref's job before its first step, even one that
  asks for the prod label while a master job started the runner. `check-cluster-api-ci.py` fails
  a pool of a master-only stack (`pull_request_plans_enabled: false`) without `allowed_refs`.
- `check-cluster-api-ci.py` (lint, validate-all) fails an in-vpc instance whose label has no runner
  pool, or whose clusters do not admit the pool's security group; a pool missing from its
  stack's `iam/ci` `ci_runner_pool_names`; and an instance whose providers exec a command
  (`aws eks get-token`) without its tool in `dependencies.tools` (the atmos image has no aws CLI). An instance with
  `settings.github.actions_enabled: false` instead is left to an operator.

Break-glass, or before the runners exist: an operator applies them through the VPC with their own
role, a named cluster admin (the creator gets no implicit admin, and the CI apply role trusts only
GitHub OIDC on master):

1. Once per stack, the owner names the role (full ARN, path kept, e.g.
   `arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<sso-region>/AWSReservedSSO_AdministratorAccess_<hash>`
   (`<sso-region>` is the IAM Identity Center home region, not the stack's),
   from `aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`) in two places:
   `map_additional_iam_roles` (`groups: ["system:masters"]`) in the stack's `components/globals.yaml`,
   which gives every `eks` instance an `AmazonEKSClusterAdminPolicy` access entry; and
   `backend/main`'s `access_roles.write` (dev/staging) or `.prod_write` (prod) in
   `stacks/orgs/fnx/root/us-east-1.yaml`, so it can write the stack's state. Apply `backend/main`
   (administrator) and let CD apply `eks/*`. `check-cluster-api-ci.py` fails a role missing from the
   backend and warns while a stack has none.
2. On the laptop, with that role's credentials (`aws sso login --profile <profile>`, then
   `export AWS_PROFILE=<profile>`), forward the endpoint through `ec2/bastion` (a private subnet of
   `vpc/main`; SSM agent via `enable_ssm`, the default, reaching SSM through the NAT gateway). Every
   `eks` instance admits the bastion's security group on 443 (`allowed_security_group_ids` in the
   stack's `components/compute.yaml`); `eks/data` in `vpc/services` is reached over
   `network/vpc-peering`, whose CIDRs both vpcs' private NACLs admit
   (`private_network_acl_peer_cidr_blocks`). That relies on a private-only endpoint (public access
   off): public DNS then returns the private IPs, which is how the bastion in `vpc/main` resolves
   them; with public access on, public DNS returns public IPs. `check-cluster-api-ci.py` fails a
   private cluster with in-cluster instances and no such ingress, peering or NACL entry. Atmos,
   terraform and the credentials stay local:

   ```bash
   host=$(aws eks describe-cluster --name <cluster> --query cluster.endpoint --output text | sed 's|https://||')
   aws ssm start-session --target <bastion-instance-id> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters "host=$host,portNumber=443,localPortNumber=443"
   echo "127.0.0.1 $host" | sudo tee -a /etc/hosts   # remove when done
   ```

   The `kubernetes`/`helm` providers take `host` from `eks/<instance>`'s state and `aws eks
   get-token` for auth, so the hosts entry makes them connect to the forward under the real
   hostname: TLS verifies against the cluster CA with no provider or kubeconfig override. Local port
   443 may need root (Linux). One cluster at a time.
3. After `eks/<instance>` and each instance the component reads:

```bash
atmos terraform deploy <component> -s <stack>   # e.g. eks-addons/main, then eks-backend-services/main
atmos workflow deploy-addons -f deploy-full-stack -s <stack>   # or the layer: platform, addons, services
```

CD moving `deployed/<stack>` does not mean these were applied.

## Changing infrastructure

Normal path: a PR (CI plans and comments), then merge (CD deploys). A rename, module move or
`count`/`for_each` change gets a `moved {}` block next to the resource; `atmos terraform state mv`
is the fallback for moves configuration cannot express. A moved-only change must plan
`0 to add, 0 to change, 0 to destroy` in every stack. `moved` cannot help when there is no old
object: an inline attribute promoted to a resource, a `ForceNew` replacement, or an instance
switched to a different root module (import instead).

A renamed output or variable breaks its stacks silently: Atmos writes an undeclared var into the
varfile and Terraform drops it with a warning, and a `!terraform.state` read of a missing output
yields null. `check-dependencies.py` (validate-all) fails both, so rename the stack side in the
same PR.

### Template fixtures

Each `stacks/catalog/templates/<t>.yaml` has a never-deployed stack `fnx-ue1-fixtures-<name>`
(`stacks/orgs/fnx/fixtures/us-east-1/<name>.yaml`; short names, since templates put the environment
into length-limited AWS names), so lint, validate-all and plan-sweep check templates no real stack
imports. A fixture listed in `KNOWN_BROKEN_FIXTURES` (`workflows/scripts/common/fixtures.py`) has
the listed checks' failures printed as `KNOWN-BROKEN` without failing (`ALL` lists every check); a
template port PR removes its entry, which makes the fixture strict. plan-sweep skips a fixture whose
entry is `ALL` with one `SKIP` line, even when you name it on the command line (check-dependencies
still reports it); to sweep it, narrow the entry to the checks that still fail.

Templates ship non-prod values for their databases and caches and leave the prod ones to the
importing stack (each template's ENVIRONMENT-SPECIFIC OVERRIDES). `check-prod-protection.py` (in
`lint` and `validate-all`) fails a stage `prod` rds instance that is not `environment: prod`,
Multi-AZ, deletion-protected (`deletion_protection`, `prevent_destroy`), without a final snapshot
or with under 7 days of backups, and a prod elasticache instance without failover across AZs (at
least 2 nodes) or with under 7 days of snapshots. Unset values count as the component's defaults.

## Lambda packages

Function code lives in an application repo, not here (the Cloud Posse aws-lambda model). The
contract:

1. Set `lambda_uploader_trusted_github_repos: ["<org>/<app-repo>:<branch>"]` on the stack's `iam/ci`
   and apply it. Its output `lambda_uploader_role_arn` (`<prefix>-lambda-uploader`) is the role
   the app's workflow assumes with GitHub OIDC from that branch only; output
   `lambda_artifacts_bucket_name` is the bucket, `<Environment>-lambda-artifacts-<account id>`.
   The role may put and read objects in that bucket and use `kms/main` through S3, nothing else.
2. The app CI uploads each build to `<function_name>/<version>.zip` (`function_name` as in the
   instance's vars) as a conditional write: `aws s3api put-object --if-none-match '*'`, or the
   same header on `complete-multipart-upload` for a multipart upload. The role allows
   `s3:PutObject` only with `s3:if-none-match`, so released keys are immutable: re-uploading a
   released version fails (412, or AccessDenied without the header) by design; build a new version.
3. A PR here sets the instance's `settings.package_version` to `"<version>"`, quoted (an unquoted
   `1.10` is the YAML float `1.1`, and `check-lambda-packages.py` rejects it); the changed `s3_key`
   is what redeploys the function when CD applies the merge. Roll back by setting an earlier
   version.

First release of a function: upload, set `package_version`, set `metadata.enabled: true` on the
`lambda/*` instance, and restore its readers (each marked with a `disabled` comment in
`components/services.yaml`: apigateway/main's `/api` route and `apigateway/data` for
`data-processor`, `monitoring/data`'s dimensions for every function). `check-lambda-packages.py`
(in `lint`) fails an enabled instance still on the `unreleased` placeholder, and an `iam/ci` whose
bucket name or KMS alias no longer matches the stack's `s3/lambda-artifacts` and `kms/main`.

Triggers come up with their function: `data-transformer` polls `sqs/data-transform` (staging,
prod; the queue deploys in the storage layer, before the function), which `data-processor` sends
to; `report-generator` (prod) runs daily at 06:00 UTC. Messages that fail 5 receives move to
`<Environment>-data-transform-dlq` (kept 14 days); after a fix, redrive them from the SQS console
or `aws sqs start-message-move-task --source-arn <dlq arn>`. A change to `data-transformer`'s
`timeout` needs the queue's `visibility_timeout_seconds` (6x timeout + 5) changed with it.

## Day-2 tasks

| Task | Command |
|------|---------|
| Drift (hourly in CI, [in-cluster components](#in-cluster-components) on the in-VPC runners) | `atmos workflow drift-detection -f drift-detection -s <stack>` |
| Security scan | `atmos workflow security-scan -f lint` (fails on HIGH/CRITICAL); `security-scan-report -f lint` lists every finding without failing. No baselines: fix a finding or suppress it inline with a reason (`#checkov:skip=<ID>:<reason>` in the block, `#trivy:ignore:<ID> <reason>` above it) |
| Security Hub findings | `atmos workflow security-audit -f security-hardening -s <stack>` |
| Compliance | `atmos workflow check -f compliance-check -s <stack>`; `report` writes `compliance-report.md` |
| Hardening | `STACK=<stack> atmos workflow harden -f security-hardening` (plans and applies `cloudtrail`, `awsconfig`, `guardduty`, `securityhub`), `harden-iam` (password policy) |
| Import a resource | `atmos workflow import -f import -s <stack>` |
| List / release locks | `STACK=<stack> atmos workflow list-locks -f state-operations`; `atmos workflow force-unlock -f state-operations -s <stack>` (only when nothing is running) |
| Rotate a Secrets Manager/Kubernetes certificate | `atmos workflow rotate -f rotate-certificate` (ACM certificates are Terraform-managed) |
| Destroy a stack / the backend | `atmos workflow destroy -f destroy-environment` / `-f destroy-backend`; both prompt for the stack name, do not pass `-s` |

Destroying the backend is irreversible: it deletes the bucket and every stack's state in it.

### Pinned versions: providers, the Atmos image, actions

Dependabot (`.github/dependabot.yml`) opens weekly grouped PRs for all three; each must pass
`CI gate`. `.github/CODEOWNERS` requests the owner's review on `.github/`, `iam`, `backend` and the
stacks' `security.yaml` (advisory until branch protection requires code-owner review).

- **Providers.** Every root module commits a `.terraform.lock.hcl` for `linux_amd64` (CI and
  the amd64 devops container), `darwin_arm64` and `darwin_amd64` (developer Macs), plus a
  `linux_arm64` hash nothing currently needs (kept to avoid re-locking every root), and
  every CI init runs with `-lockfile=readonly` (`TF_CLI_ARGS_init`, plus explicit flags in
  validate-all, plan-sweep and terraform-test), so an unlocked provider fails init.
  `atmos.yaml` sets `init.upgrade: never` for the same reason. After a `required_providers`
  change, or to take newer releases within the constraints:
  `atmos workflow providers-lock -f providers` (`UPGRADE=false` keeps the locked versions; a
  `COMPONENTS="kms vpc"` subset run defaults to `UPGRADE=false`, so add `UPGRADE=true` to take newer
  releases there), then commit the locks. A new major is a deliberate constraint change; Dependabot ignores majors.
- **Atmos image.** Every workflow runs `ghcr.io/cloudposse/atmos:<tag>@sha256:<digest>`, one
  literal repeated (there is no `vars` override: a digest needs a fixed tag). Dependabot bumps the
  copy in `.github/atmos-image/Dockerfile`; run `bash scripts/sync-atmos-image.sh` on its branch
  (the actionlint job fails until you do). By hand: put the new tag and the digest of its manifest
  index (`docker buildx imagetools inspect ghcr.io/cloudposse/atmos:<tag>`, or the ghcr registry
  API) in that Dockerfile and run the script; it also sets `atmos-version` in `emulator.yml`.
  Then, with that Atmos version installed, re-pin the stack manifest schema
  (`atmos stack schema schemas/atmos/atmos-manifest.json`) and commit it; the lint step
  `manifest-schema` fails in CI until the pin matches the image's Atmos.
  Raise `version.constraint` in `atmos.yaml` and `.atmos.env` when the new version is required.
- **Actions.** `uses:` refs are commit SHAs with a version comment; Dependabot moves both.

Drift fix: codify an intended manual change in the stack, then `atmos terraform deploy`; otherwise
re-apply; import resources created outside Terraform.

Bastion SSH keys are generated per instance and stored in Secrets Manager at
`ssh-key/<Environment>/<name>`. Read `private_key_openssh`, not `private_key_pem`:
`scripts/certificates/export-ssh-key.sh -r us-east-1 -s ssh-key/<Environment>/bastion -o bastion.key`.
The key is also in Terraform state.

## State restore and disaster recovery

The state bucket is versioned. List versions of a component's state:

```bash
STACK=<stack> COMPONENT_PREFIX=<component>/ atmos workflow recover-state -f disaster-recovery
```

Restoring a version needs **management-account administrator credentials**: by design no access
role has `s3:GetObjectVersion`. Run the `aws s3api copy-object --copy-source
"<bucket>/<key>?versionId=<id>"` command the workflow prints, then plan the component before
applying anything.

```bash
STACK=<stack> atmos workflow dr-status -f disaster-recovery          # readiness report
STACK=<stack> atmos workflow recover-database -f disaster-recovery   # RDS snapshots, PITR windows
```

### Disaster recovery

Prod only (owner decision Q5): `fnx-ue1-prod` (us-east-1) fails over to `fnx-ue2-prod` (us-east-2),
a warm standby in the same account. Dev and staging have no DR stack; they are rebuilt from Git.
What runs in `fnx-ue2-prod` while `fnx-ue1-prod` serves:

| Component | Warm state in `fnx-ue2-prod` | On failover |
|-----------|------------------------------|-------------|
| `vpc/main`, `iam/ci`, `acm/main`, GuardDuty, Security Hub, Config, `backup/main` | full | nothing |
| KMS | `fnx-ue1-prod` `kms/main`'s multi-region replica, alias `ue2-main` (no `kms/main` here) | nothing |
| `rds/main` | cross-region read replica of `fnx-ue1-prod`'s (`replicate_source_db`), `db.r5.large` | promote (CLI) |
| `elasticache/main` | Global Datastore secondary, 2 nodes | promote (CLI) |
| `eks/main` | `workers` at 2 nodes, `monitoring`/`memory-optimized` at 0 | scale up (CLI) |
| `eks-backend-services/main` | `metadata.enabled: false` | deploy |
| `apigateway/main` | SECONDARY half of `api.<domain>`'s Route 53 failover pair | automatic |
| `rds/data`, `vpc/services`, `eks/data` | not run | restore `rds/data` from backup copies |
| Cognito | not replicated (AWS has no cross-region user pools) | see below |

`backup/main` in `fnx-ue1-prod` copies every recovery point to `ue1-backup-replica` in us-east-2.
Readiness: `STACK=fnx-ue1-prod atmos workflow dr-status -f disaster-recovery` (it reports both
vaults and the state bucket's replication) and the same for `fnx-ue2-prod`. CD deploys
`fnx-ue2-prod` right after `fnx-ue1-prod`, whose state it reads (`kms/main`, `rds/main`,
`elasticache/main`, `network/main`, `iam/ci`): its `settings.dr.standby_of: fnx-ue1-prod` orders it
(`ci-stacks.py`), not the stack names. Each region's `apigateway/main` health check has a
`HealthCheckStatus` alarm in us-east-1 on `ue1-main-alarms`. Both alarms and that topic live in
us-east-1 (Route 53 publishes health check metrics only there), so a us-east-1 outage silences
them; the DNS failover itself does not depend on them. The signal outside us-east-1 is
`fnx-ue2-prod`'s own API alarms (`apigateway/main` 5xx and latency, `create_performance_alarms`)
on its `ue2-main-alarms` topic in us-east-2: they fire when the failed-over traffic errors.

**Failover** (`STACK=fnx-ue1-prod atmos workflow dr-failover -f disaster-recovery` prints these
steps; operator only, never from CI). It is CLI-first: a us-east-1 outage takes the state bucket
with it, so nothing here needs Terraform. Terraform catches up after recovery (below).

1. Freeze CD: `gh workflow disable terraform-cd.yml`, and merge nothing until the reconciliation
   below. A merge would apply against a primary that is gone.
2. DNS fails over by itself: `api.<domain>` answers from us-east-2 once `fnx-ue1-prod`'s health
   check on its stage root fails three times (90 s); the health check alarm notifies. This is
   Route 53's data plane, which keeps running when its us-east-1 control plane does not. To check
   it, or to force it when us-east-1 answers but is unusable (the control plane must be up):

   ```bash
   aws route53 list-health-checks --query 'HealthChecks[].[Id,HealthCheckConfig.FullyQualifiedDomainName]'
   aws route53 get-health-check-status --health-check-id <ue1 id>
   aws route53 update-health-check --health-check-id <ue1 id> --inverted   # force us-east-1 unhealthy
   ```

3. Promote the database and give it its own master secret (the replica used the source's, whose
   secret is in us-east-1):

   ```bash
   aws rds promote-read-replica --db-instance-identifier ue2-prod-main-db --region us-east-2
   aws rds wait db-instance-available --db-instance-identifier ue2-prod-main-db --region us-east-2
   aws rds modify-db-instance --db-instance-identifier ue2-prod-main-db --region us-east-2 \
     --manage-master-user-password --master-user-secret-kms-key-id alias/ue2-main --apply-immediately
   ```

4. Promote the cache:

   ```bash
   aws elasticache describe-global-replication-groups --region us-east-2 \
     --query 'GlobalReplicationGroups[].GlobalReplicationGroupId'
   aws elasticache failover-global-replication-group --region us-east-2 \
     --global-replication-group-id <id> \
     --primary-region us-east-2 --primary-replication-group-id ue2-prod-cache
   ```

   If us-east-1 is too far gone for the failover to complete, detach the secondary instead; it
   becomes a standalone writable cache, and failback then rebuilds the pair (below):
   `aws elasticache disassociate-global-replication-group --region us-east-2
   --global-replication-group-id <id> --replication-group-id ue2-prod-cache
   --replication-group-region us-east-2`.
5. Scale the node groups to `fnx-ue1-prod`'s sizes (`workers` 3/6/12, `monitoring` 2/3/4,
   `memory-optimized` 2/3/6 as min/desired/max). The names carry a random suffix:

   ```bash
   aws eks list-nodegroups --cluster-name ue2-main --region us-east-2
   aws eks update-nodegroup-config --cluster-name ue2-main --region us-east-2 \
     --nodegroup-name <workers-...> --scaling-config minSize=3,desiredSize=6,maxSize=12
   ```

6. Deploy the in-cluster services, `eks-backend-services/main`, from inside the VPC
   ([In-cluster components](#in-cluster-components)). It has never been applied in
   `fnx-ue2-prod`, so it has no state of its own to fork: with the state bucket down it applies
   with local state, migrated after recovery, while its `!terraform.state` inputs read the
   bucket's us-east-2 replica
   ([State during a us-east-1 outage](#state-during-a-us-east-1-outage)). The replica holds the
   state from before the CLI steps, so on a branch (`stacks/orgs/fnx/prod/us-east-2/components/compute.yaml`):

   | Input | From the replica | On the branch |
   |-------|------------------|---------------|
   | `metadata.enabled` | `false` | `true` (Atmos skips a disabled instance) |
   | `database_secret_arn` (`rds/main .password_secret_arn`) | null: the replica had no secret, and the validation rejects null | the secret step 3 created: `aws rds describe-db-instances --db-instance-identifier ue2-prod-main-db --region us-east-2 --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text` |
   | `database_name` (`rds/main .instance_name`) | a replica's `db_name`, possibly null | `productionapp`, the promoted instance's (`fnx-ue1-prod`'s) |
   | `cluster_secret_store_name` (`external-secrets/main`) | its output, if it was applied while warm | `aws-secretsmanager` (its default store); if it was never applied, deploy it first the same way |
   | `database_endpoint`, `cluster_name`, `host`, `cluster_ca_certificate` | unchanged by the failover | keep |
   | `redis_host`, `redis_port`, `redis_secret_arn` (`elasticache/main`) | the secondary's own endpoint and AUTH secret (`redis-auth/ue2/...`), which promotion keeps | keep |

   ```bash
   export TFSTATE_SOURCE=replica          # !terraform.state reads go to the us-east-2 replica
   rm -f components/terraform/eks-backend-services/backend.tf.json
   atmos terraform deploy eks-backend-services/main -s fnx-ue2-prod --auto-generate-backend-file=false
   ```
7. Analytics, if needed: restore `rds/data` from `ue1-backup-replica` in us-east-2
   (`aws backup list-recovery-points-by-backup-vault --backup-vault-name ue1-backup-replica
   --region us-east-2`, then `aws backup start-restore-job`).
8. Verify: `curl -sf https://api.<domain>/` and
   `STACK=fnx-ue2-prod atmos workflow dr-status -f disaster-recovery`.

Cognito: `/api` (the only authorized route) is disabled today, so nothing fails over. When it is
enabled, `fnx-ue2-prod`'s `apigateway/main` needs an authorizer whose pool exists in us-east-2.

**Reconcile Terraform** once the state bucket answers again (us-east-2 still primary). Each PR's
plan is read before merging; re-enable CD for these merges only (`gh workflow enable
terraform-cd.yml`) or apply them from an operator machine:

1. `fnx-ue2-prod` `rds/main`: remove `replicate_source_db`. The promotion plan check, before any
   Terraform promotion: `atmos terraform plan rds/main -s fnx-ue2-prod` must show
   `aws_db_instance.main` updated in place, never replaced (`-/+`). `db_name` and `username` force
   a replacement, so they must match the promoted instance: `db_name` is set equal to
   `fnx-ue1-prod`'s (`productionapp`) and both stacks use the component's default `username`. A
   replacement in the plan means stop, not apply.
2. `fnx-ue2-prod` `eks/main`: the node groups' `min_group_size`/`desired_group_size` to the sizes of
   step 5 (Terraform ignores `desired_size` drift, not `min_size`).
3. `fnx-ue2-prod` `eks-backend-services/main`: `metadata.enabled: true`, its inputs back to the
   `!terraform.state` reads (the step 6 literals now match `rds/main`'s reconciled outputs); migrate its local state
   into the bucket first if step 6 used one.
4. Apply neither stack's `elasticache/main` while the cache primary is in us-east-2:
   `fnx-ue1-prod`'s plan would replace the Global Datastore (its primary moved). Failback restores
   the pair first.
5. Leave `fnx-ue1-prod` alone until failback; its stale `rds/main` is replaced there.

**Failback** (`STACK=fnx-ue1-prod atmos workflow dr-failback -f disaster-recovery`), once
us-east-1 and the state bucket are healthy. `replicate_source_db` does not force a replacement in
the AWS provider, and AWS cannot turn a standalone instance into a replica, so each re-seed is an
explicit `-replace` from an operator, not a merge:

1. Re-seed `fnx-ue1-prod`'s database from us-east-2:
   1. Lift its deletion protection (the prod validation keeps it on in Terraform):
      `aws rds modify-db-instance --db-instance-identifier ue1-prod-main-db
      --no-deletion-protection --apply-immediately --region us-east-1`.
   2. The replacement deletes the old instance with a final snapshot of a fixed name,
      `ue1-prod-main-db-final-snapshot`, and fails if one exists from an earlier failback. Keep
      that one under a dated name, then delete it:

      ```bash
      SNAP=ue1-prod-main-db-final-snapshot; KEEP="$SNAP-$(date -u +%Y%m%d%H%M)"; R=us-east-1
      if aws rds describe-db-snapshots --db-snapshot-identifier "$SNAP" --region "$R" >/dev/null; then
        aws rds copy-db-snapshot --source-db-snapshot-identifier "$SNAP" \
          --target-db-snapshot-identifier "$KEEP" --copy-tags --region "$R"
        aws rds wait db-snapshot-available --db-snapshot-identifier "$KEEP" --region "$R"
        aws rds delete-db-snapshot --db-snapshot-identifier "$SNAP" --region "$R"
      fi   # DBSnapshotNotFound above: nothing to set aside
      ```

   3. On a branch, set `fnx-ue1-prod`'s `rds/main`
      `replicate_source_db: "arn:aws:rds:us-east-2:{{ .settings.environment.account_id }}:db:ue2-prod-main-db"`
      (a literal ARN: a `!terraform.state` read of `fnx-ue2-prod` would invert the two stacks'
      deploy order). From that branch:
      `atmos terraform plan rds/main -s fnx-ue1-prod -- -replace=aws_db_instance.main` shows the
      replacement, then
      `atmos terraform apply rds/main -s fnx-ue1-prod -- -replace=aws_db_instance.main`. Merge the
      PR afterwards; CD then has nothing to change.
   4. Wait until `ReplicaLag` of `ue1-prod-main-db` (CloudWatch, `AWS/RDS`, us-east-1) is 0.
2. In a maintenance window, stop writes in us-east-2 (scale the backend deployments to 0), check
   the lag is 0, then promote `ue1-prod-main-db`: a PR removing that `replicate_source_db`, with the
   promotion plan check above on `fnx-ue1-prod` (update in place only), merged and applied.
3. Move the cache primary back: `aws elasticache failover-global-replication-group --region
   us-east-1 --global-replication-group-id <id> --primary-region us-east-1
   --primary-replication-group-id ue1-prod-cache`. If failover step 4 detached the secondary, the
   pair is rebuilt instead: `fnx-ue1-prod`'s cache becomes a new Global Datastore primary
   (`atmos terraform apply elasticache/main -s fnx-ue1-prod`), and `fnx-ue2-prod`'s
   joins it again with `-replace=aws_elasticache_replication_group.main`.
4. Un-invert the health check if failover step 2 inverted it
   (`aws route53 update-health-check --health-check-id <ue1 id> --no-inverted`): DNS returns to
   us-east-1.
5. Make `fnx-ue2-prod`'s database a replica of us-east-1 again, the same way as step 1: lift
   `ue2-prod-main-db`'s deletion protection (in us-east-2), set aside
   `ue2-prod-main-db-final-snapshot` if it exists, restore
   `replicate_source_db: !terraform.state rds/main fnx-ue1-prod .instance_arn` on a branch, and
   `atmos terraform apply rds/main -s fnx-ue2-prod -- -replace=aws_db_instance.main`; merge.
6. Back to warm: a PR reverting reconciliation steps 2 and 3, and the desired sizes Terraform
   ignores by CLI (`update-nodegroup-config ... --scaling-config minSize=2,desiredSize=2,maxSize=12`
   for `workers`, `0/0/<max>` for the others).
7. Re-enable CD: `gh workflow enable terraform-cd.yml`.

## Deploys green, does not serve

`cognito/main` has no users or identity provider, so `/api` rejects every request; `apigateway` `/` is a `MOCK`
liveness endpoint by design.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` cannot assume `fnx-terraform-backend-*-role` | Run `backend-cold-start`, or add the caller's role ARN to that stage's `access_roles` in `stacks/orgs/fnx/root/us-east-1.yaml` |
| CI plan: AccessDenied on `PutObject` at `workspace new` | Read roles cannot create a workspace; the instance's first deploy does |
| `Error acquiring the state lock` | Another run holds it; `list-locks`, then `force-unlock` if abandoned |
| `!terraform.state` returns nothing | The referenced instance is not deployed in that stack yet; deploy in layer order |
| A string input rejects a `!terraform.state` value as an object | The output is a JSON string (a `*_policy`); end the read with `\| tojson` |
| ACM validation times out after 45 minutes | The stack's domain is not delegated; see [Deploying a stack](#deploying-a-stack) |
