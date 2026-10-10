# Operations

Bootstrap, deploy and run the stacks; the developer side is in the [README](../README.md).
Workflows shown with `-s <stack>` take the flag; those shown with `STACK=<stack>` read the
variable (or prompt).

## First-deploy inputs

The stacks hold placeholders. Replace them before any apply against a real account.

| Input | Where |
|-------|-------|
| Account IDs | `settings.account_map.full_account_map` in `stacks/orgs/fnx/_defaults.yaml`, the only place: `root` (management), `dev`, `staging`, `prod`, `prod-eu` (the EU prod account, `fnx-ew1-prod` and its DR stack `fnx-ec1-prod`; GDPR keeps it apart from `prod`). Each stage's `settings.environment.account_id` (`fnx-ew1-prod`'s and `fnx-ec1-prod`'s from `prod-eu`), `management_account_id`, the backend `access_roles` ARNs in `fnx-ue1-root` and `fnx-ew1-root` and every provider's `allowed_account_ids` are read from it, so that guard fails every real plan and apply until the map holds the real IDs. `scripts/new-environment.sh` adds a new account here (`AWS_ACCOUNT_ID`). The emulator and fixture stacks keep the emulator's `000000000000` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` |
| Cross-account role callers | `trusted_principal_arns` in `stacks/catalog/iam/defaults.yaml`: the management-account role ARNs (path included) allowed to assume each workload account's `-CrossAccountRole`. The placeholder `<tenant>-cross-account-operator` matches nobody until it exists |
| Cognito feature plan | `user_pool_tier: PLUS` with `advanced_security_mode: ENFORCED` in `stacks/catalog/cognito/defaults.yaml`: PLUS is billed from the first monthly active user. `OFF` + `ESSENTIALS` per instance is the cheaper choice |
| Domains | `settings.environment.domain_name` in each stack's `components/globals.yaml`; every zone, record, certificate and API domain derives from it (`fnx-ew1-prod`: the EU apex placeholder `fnx-eu.example.com`, also its `acm/main` certificate's names; `fnx-ec1-prod` repeats it, its DR standby serving the same apex) |
| Alert recipients | `alarm_email_subscriptions` on monitoring instances and the lists in `components/globals.yaml` (`settings.environment.monitoring`, which `backup/main`'s `notification_emails`, `cost-optimization/main`'s budget and anomaly emails read; `fnx-ew1-prod`'s and `fnx-ec1-prod`'s are copies of `fnx-ue1-prod`'s `example.com` placeholders); each address must confirm its SNS subscription. GuardDuty, Security Hub and Inspector findings reach people only through each stack's `security-monitoring/main` topic, whose `security_email_subscriptions` is empty everywhere (a preflight notice per stack) |
| Budgets | `monthly_budget_limit` on each stack's `cost-optimization/main`, read from `settings.environment.monitoring.budget_monthly_limit` in `components/globals.yaml` (USD: dev 500, staging 2000, `fnx-ue1-prod` 10000; `fnx-ew1-prod` 10000, a placeholder copy of `fnx-ue1-prod`'s). Each budget counts only spend tagged with its stack's `Environment` (`ue1`, `ew1`), so a DR standby's spend (`ue2`, `ec1`, no `cost-optimization` of its own) is in no budget |
| Cost-allocation tags | the `Environment` tag activated as a user-defined cost-allocation tag in the payer (management) account's Billing console (Cost allocation tags); until then every budget's `user:Environment$<tag>` filter matches no spend and no budget alerts |
| Prod RDS alarm target | `sns_topic_arn` on prod's `rds/main` (`fnx-ue1-prod`, `fnx-ew1-prod` and their DR replicas `fnx-ue2-prod`, `fnx-ec1-prod`): unset, so its CloudWatch alarms have no action |
| Lambda packages | the application repo that builds them, as `lambda_uploader_trusted_github_repos` on each stack's `iam/ci` (`components/security.yaml`), then a first upload per function: see [Lambda packages](#lambda-packages). Until then every `lambda/*` instance is `metadata.enabled: false` |
| GitHub | default-branch protection, applied: PR required, linear history, no force-push, required check `CI gate` (the `terraform-ci.yml` job that reports on every PR and fails if any CI job failed). No tag ruleset guards `refs/tags/deployed/**`: on a personal repo GitHub Actions cannot be a ruleset bypass actor, and a ruleset without that bypass blocks `terraform-cd.yml`'s own tag moves. Add it once the repo moves to an organization |
| GitHub App | the self-hosted CI runners' just-in-time registration: a GitHub App installed on this repository (Administration read/write); its IDs in `settings.github_app` (`app_id`, `installation_id`; `0` until set) in `stacks/orgs/fnx/_defaults.yaml`; and, after each runner pool's first apply, its private key in that account's SSM, in the pool's region (`fnx-ew1-prod`'s: `prod-eu`, eu-west-1; `fnx-ec1-prod`'s: `prod-eu`, eu-central-1), at the pool's `.app_private_key_parameter_name`, encrypted with the pool's own key (`.app_key_kms_key_alias`): see `components/terraform/github-runners/README.md`. The repository is public: turn on Settings → Actions → General → "Require approval for all outside collaborators" |
| Deploy tags | one `deployed/<stack>` tag per stack: `git tag deployed/<stack> <sha> && git push origin deployed/<stack>` |
| EKS cluster admins | `map_additional_iam_roles` in each stack's `components/globals.yaml`: see [In-cluster components](#in-cluster-components). While empty, nobody can apply the in-cluster components. `fnx-ew1-prod`'s and `fnx-ec1-prod`'s roles are in the `prod-eu` account and must also be in `backend/main`'s `access_roles.prod_write` `allowed_principal_arns` in `stacks/orgs/fnx/root/eu-west-1.yaml` (`fnx-ew1-root`) |
| Backend service images | `settings.environment.backend_service_images` in each stack's `components/globals.yaml` (`eks-backend-services/main`): the release pipeline's `ghcr.io/fnx-platform/<service>:1.4.2` placeholders until it publishes real ones, flagged per stack and service; `fnx-ew1-prod`'s and `fnx-ec1-prod`'s are copies of `fnx-ue1-prod`'s |

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
- a backend service image still on the `ghcr.io/fnx-platform/<service>:1.4.2` placeholder;
- a placeholder (`0`) GitHub App ID or installation ID;
- a workload account equal to the management account;
- two stages sharing one account;
- an EU (GDPR-scoped) stack sharing an account with a US one (`prod-eu` equal to `prod`).

It prints the rows no file can settle (Cognito plan, the operator role's existence, Lambda
packages, GitHub, deploy tags, the GitHub App's key and outside-collaborator approval,
cost-allocation tags) as notices, and per stack its budget amount to confirm and an empty
`security_email_subscriptions`. The `local` and `fixtures` stacks are exempt.
`bootstrap.yaml` runs it fatally for the stack being deployed (`backend-cold-start`,
`backend-only`, `full`) before any AWS call. `atmos workflow lint` runs it with `--warn`: it
never fails, and prints the counts per row plus the first 10 findings (`--warn --all` prints
them all). It stands in for Cloud Posse's cold-start checks: there, `account-map` holds the
account IDs and the accounts layer is deployed and verified first
([deploy accounts](https://docs.cloudposse.com/layers/accounts/deploy-accounts/),
[aws-account-map](https://github.com/cloudposse-terraform-components/aws-account-map)).

## State backend

One bucket, `fnx-terraform-state` (`settings.tfstate.bucket`), in the management account, with native S3
lockfiles (`use_lockfile: true`, no DynamoDB). It is `backend/main` in `fnx-ue1-root`
(`settings.tfstate.stack`, which every `iam` instance that inherits `catalog/iam` depends on), and every stack's
backend (`stacks/orgs/fnx/_defaults.yaml`) assumes one of its access roles, so it is created first,
with management-account administrator credentials. The bucket lives in one region,
`settings.tfstate.region` (`us-east-1`), and every US stack's backend uses it whatever the stack's
own region is, so a DR stack (`fnx-ue2-prod`) keeps its state here too. S3 replicates it to
`fnx-terraform-state-replica` in `settings.tfstate.replica_region` (`us-east-2`), encrypted with
the state key's multi-region replica (`backend/main`'s `s3_replication_enabled`; see
[State during a us-east-1 outage](#state-during-a-us-east-1-outage)).

The EU stacks keep their state in the EU (GDPR residency): `backend/main` in `fnx-ew1-root`
(`stacks/orgs/fnx/root/eu-west-1.yaml`, same management account), bucket
`fnx-ew1-terraform-state` in `eu-west-1`, replicated to `fnx-ew1-terraform-state-replica` in
`eu-central-1`, roles `fnx-ew1-terraform-backend-*`. An EU stack overrides all of
`settings.tfstate` to point there; `check-data-residency.py` fails one that names a non-EU region.
It holds only prod state (`fnx-ew1-prod` and its DR stack `fnx-ec1-prod`, both in the `prod-eu`
account, whose state stays in `eu-west-1` as `fnx-ue2-prod`'s stays in `us-east-1`), so it has the
`prod_read`, `prod_write` and `root_write` roles, trusting those two stacks' CI roles.

The backend workflows default to `fnx-ue1-root`; `-s fnx-ew1-root` runs them on the EU backend
(the bucket and roles come from that stack's `settings.tfstate`):

```bash
atmos workflow backend-cold-start -f bootstrap   # once: apply with local state, then migrate it into the bucket
atmos workflow backend-only -f bootstrap         # later backend changes
atmos workflow verify -f bootstrap               # backend describe + outputs
atmos workflow backend-cold-start -f bootstrap -s fnx-ew1-root   # the EU backend (same for backend-only, verify)
atmos workflow apply -f apply-backend [-s fnx-ew1-root]          # plan + deploy, no preflight
```

An existing bucket must be imported first: see `components/terraform/backend/README.md`.

Every role also trusts the administrator who applied `backend/main`; the stack backend picks the
role from the stack's stage and `TFSTATE_ACCESS`, whoever runs it. Role names start with
`<role_prefix>` (`settings.tfstate.role_prefix`, `fnx-terraform-backend`); the CI roles' ARNs
(`iam/ci`) are built from it too.

| Role (`access_roles` key) | Access | Trusted CI role |
|---------------------------|--------|-----------------|
| `<role_prefix>-read-role` (`read`) | read, dev/staging state | dev/staging CI plan roles |
| `<role_prefix>-role` (`write`) | read/write, dev/staging state | dev/staging CI apply roles |
| `<role_prefix>-prod-read-role` (`prod_read`) | read, prod state (US: `fnx-ue1-prod`, DR `fnx-ue2-prod`; EU: `fnx-ew1-prod`, DR `fnx-ec1-prod`) | the prod stacks' CI plan roles |
| `<role_prefix>-prod-role` (`prod_write`) | read/write, prod state | the prod stacks' CI apply roles |
| `<role_prefix>-root-role` (`root_write`) | read/write, the root stack's own state (`fnx-ue1-root`, `fnx-ew1-root`) | none |

- CI plans set `TFSTATE_ACCESS=read` and plan with `-lock=false`; deploys leave it unset.
- Trust is by role ARN, listed in `access_roles` in `stacks/orgs/fnx/root/us-east-1.yaml` (EU:
  `root/eu-west-1.yaml`). Add a new stack's
  `<tenant>-<environment>-<stage>-ci-plan`/`-apply` roles there (iam/ci's `ci_role_name_prefix`),
  and any operator role that runs Terraform against a stage. `check-ci-state-roles.py` (in `lint`
  and `validate-all`) fails a CI role that its stage's read or write role, of the backend owning its
  state bucket, does not trust, or that may assume another role (`ci_backend_*_role_arn`).
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

**EU: an eu-west-1 outage.** The EU stacks' state is in `fnx-ew1-root`'s bucket,
`fnx-ew1-terraform-state` in eu-west-1, which `backend/main` there replicates
(`s3_replication_enabled`) to `fnx-ew1-terraform-state-replica` in eu-central-1, the EU DR region.
Everything above holds for it: `TFSTATE_SOURCE=replica` renders that replica for `fnx-ew1-prod`
and `fnx-ec1-prod` (their `settings.tfstate.replica_region`), read-only for the
`fnx-ew1-terraform-backend-*` roles, and `eks-backend-services/main` applies with local state:

```bash
export TFSTATE_SOURCE=replica
atmos terraform init vpc/main -s fnx-ec1-prod -- -reconfigure       # fnx-ew1-terraform-state-replica, eu-central-1
atmos terraform output rds/main -s fnx-ew1-prod
```

The EU state never touches a US bucket or region, replica included (`check-data-residency.py`), and
a us-east-1 outage leaves the EU backend untouched. `dr-status` for `fnx-ew1-prod` reports the
EU bucket's replication.

## Repository variables

| Variable | Value |
|----------|-------|
| `AWS_PLAN_ROLE_ARN` | the "AWS is configured" switch: unset = AWS jobs skip. Any non-empty value enables them (by convention a `ci_plan_role_arn`); no job assumes it |
| `AWS_REGION` | optional override (default `us-east-1`) of the hosted jobs' credentials region; the in-VPC jobs (`in-vpc.yml`) always use their runner pool's `vars.region` |

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
with the child stack's `zone_name_servers.main`, and deploy prod's `network/main`. EU prod
(`fnx-ew1-prod`) has its own apex, never under the US domain: delegate it at its registrar to
`fnx-ew1-prod`'s `network/main` `zone_name_servers.main`.
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
- Every runner serves master only. Every in-VPC job runs on the default branch, the apply roles
  that start runners trust only master's OIDC subject, and every pool sets
  `allowed_refs: [refs/heads/master]` (`catalog/github-runners/defaults`): the runner's
  job-started hook fails any other ref's job before its first step, even one that asks for a
  pool's label while a master job started the runner. `check-cluster-api-ci.py` fails a pool
  without `allowed_refs`.
- Demand per pool is bounded: CD (serialized by `terraform-cd-main`), one plan
  (`in-vpc-plan-<stack>-<asg>`) and one drift check (`in-vpc-drift-<stack>-<asg>`) at most, and
  every pool's `max_size` must be at least 3 (`check-cluster-api-ci.py`). A job that finds its
  pool full fails ("runner pool ... is full") rather than queueing for a runner that never starts
  (github-runners README, "Bounded demand").
- A refused job does not cost a runner: the instance powers off without lowering desired
  capacity and the pool launches a replacement for the next queued job, so jobs queued for a
  label cannot starve the master job that started the runner. Runners have no Auto Scaling
  permission: each leaves by deleting its own lease parameter, and the pool's `jit` function ends
  it (github-runners README).
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
least 2 nodes) or with under 7 days of snapshots, and a prod cognito pool without
`deletion_protection`. Unset values count as the component's defaults.

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
| `cognito/main` | its own pool, filled from `fnx-ue1-prod`'s by `lambda/cognito-user-migration` on each user's first sign-in or reset | nothing (see [Auth during failover](#auth-during-failover)) |

`backup/main` in `fnx-ue1-prod` copies every recovery point to `ue1-backup-replica` in us-east-2;
the EU's, in `fnx-ew1-prod`, to `ew1-backup-replica` in eu-central-1 (never a US region).
Readiness: `STACK=fnx-ue1-prod atmos workflow dr-status -f disaster-recovery` (it reports both
vaults and the state bucket's replication) and the same for `fnx-ue2-prod`. CD deploys
`fnx-ue2-prod` right after `fnx-ue1-prod`, whose state it reads (`kms/main`, `rds/main`,
`elasticache/main`, `network/main`, `iam/ci`): its `settings.dr.standby_of: fnx-ue1-prod` orders it
(`ci-stacks.py`), not the stack names. That order also validates `fnx-ue2-prod`'s `acm/main`
(`api.<domain>`): it writes no validation record (`process_domain_validation_options: false`) and
waits on the one `fnx-ue1-prod`'s `acm/main` writes for its `*.api.<domain>` SAN, the same CNAME
in one account. CD deploys with fail-fast false, so if the primary's `acm/main` fails on a first
deploy, the DR `acm/main` still runs and fails after the 45 minute validation timeout: fix the
primary and re-run. Each region's `apigateway/main` health check has a
`HealthCheckStatus` alarm in us-east-1 on `ue1-main-alarms`. Both alarms and that topic live in
us-east-1 (Route 53 publishes health check metrics only there), so a us-east-1 outage silences
them; the DNS failover itself does not depend on them. The signal outside us-east-1 is
`fnx-ue2-prod`'s own API alarms (`apigateway/main` 5xx and latency, `create_performance_alarms`)
on its `ue2-main-alarms` topic in us-east-2: they fire when the failed-over traffic errors.

The EU pair is built the same way: `fnx-ew1-prod` (eu-west-1) fails over to `fnx-ec1-prod`
(eu-central-1), a warm standby in the same `prod-eu` account, so EU data never leaves the EU
(`check-data-residency.py`). Its state is in the EU backend (`fnx-ew1-root`, eu-west-1) and its
`settings.dr.standby_of: fnx-ew1-prod` has CD deploy it right after `fnx-ew1-prod`, whose state it
reads (`kms/main`, `iam/ci`, `acm/main`, `network/main`, `rds/main`, `elasticache/main`,
`cognito/main`). The table above holds for it with ec1 for ue2: the replica key is alias
`ec1-main`, `rds/main` replicates `fnx-ew1-prod`'s, `elasticache/main` is the secondary of
`fnx-ew1-prod`'s Global Datastore (`fnx-ew1-prod-cache`), `cognito/main` migrates users from
`fnx-ew1-prod`'s pool (its `dr-migration` client), `acm/main` waits on `fnx-ew1-prod`'s
`*.api.<EU apex>` validation record, and `apigateway/main` is the SECONDARY of `api.<EU apex>`.
Neither EU stack has `rds/data`, `vpc/services` or `eks/data`; `fnx-ew1-prod`'s backups are copied
to `ew1-backup-replica` in eu-central-1.

The one part outside the EU is Route 53's health checking of `api.<EU apex>` (owner decision B5).
What sits in us-east-1 is configuration only, with no personal data and nothing persisted: the two
health checks, their `HealthCheckStatus` alarms (Route 53 publishes the metric only there) and,
per alarm, an EventBridge rule, its targets and their IAM role. No topic, key, email address,
archive or queue is there: the `apigateway` component has no input for one, and an EU alarm
action (`health_check_alarm_actions`, a us-east-1 topic) fails `check-data-residency.py`.
The checks call from eu-west-1, us-east-1 and ap-southeast-1: Route 53 needs three checker
regions and eu-west-1 is the only EU one (the EXEMPTIONS entries). Each alarm notifies nothing in
us-east-1; its rule relays the alarm's state changes to the default event bus of both EU regions
(`apigateway/main` `health_check_alarm_relay_regions`), where each stack's `monitoring/main`
(`receive_relayed_health_check_alarms`) delivers them to its topic, `ew1-main-alarms` and
`ec1-main-alarms`. So the PRIMARY's alarm still reaches `ec1-main-alarms` during an eu-west-1
outage, and a recipient subscribed to both topics gets each state change twice: intentional
redundancy (`fnx-ec1-prod` can get its own recipients once the real addresses land). As in the US, a us-east-1 outage silences both alarms, not the failover;
`fnx-ec1-prod`'s API alarms on `ec1-main-alarms` (eu-central-1) are the in-region signal.

The failover, reconciliation and failback steps below are written with the US pair's names; the
EU pair runs the same steps with the names in [EU failover](#eu-failover). `dr-failover` and
`dr-failback` print each pair's own steps: `workflows/scripts/common/dr-pair.py` derives the
standby (the stack whose `settings.dr.standby_of` names `STACK`), its region and every resource
name from the stacks' config, and refuses any other stack (a standby, dev, staging) with the
reason. `dr-status` reports the DR region from the same config (`backup/main`'s
`replica_region`, else the standby's region): us-east-2 for the US pair, eu-central-1 for the EU
one; `DR_REGION` overrides it.

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
8. Auth needs no step while us-east-1's Cognito answers: users sign in again and are migrated
   ([Auth during failover](#auth-during-failover)). If it does not, import the users not yet in
   us-east-2 from the latest export (the bulk import there); they reset their password by email.
9. Verify: `curl -sf https://api.<domain>/` and
   `STACK=fnx-ue2-prod atmos workflow dr-status -f disaster-recovery`.

The standby runs below the primary's sizes (owner decision 2026-10-07). Step 5 restores the
node groups; the database (`db.r5.large`, the primary's is `db.r5.xlarge`) and the cache (2
nodes, the primary's 3) serve as they are, and are resized only if the load needs it (a
modify, not a replacement), in the standby's region:
`aws rds modify-db-instance --db-instance-identifier ue2-prod-main-db --db-instance-class db.r5.xlarge --apply-immediately --region us-east-2`,
`aws elasticache increase-replica-count --replication-group-id ue2-prod-cache --new-replica-count 2 --apply-immediately --region us-east-2`.
A resized database's `instance_class` joins reconciliation step 1, and failback step 5 sets the
warm one back before its `-replace`; the cache's added replica stays out of Terraform (reconciliation
step 4) and failback step 6 removes it by CLI.

#### EU failover

`fnx-ew1-prod` (eu-west-1) fails over to `fnx-ec1-prod` (eu-central-1) with the steps above
(`STACK=fnx-ew1-prod atmos workflow dr-failover -f disaster-recovery`, and `dr-failback` the same),
reading each name in its EU form:

| In the steps | US pair | EU pair |
|--------------|---------|---------|
| Primary, standby | `fnx-ue1-prod`, `fnx-ue2-prod` | `fnx-ew1-prod`, `fnx-ec1-prod` |
| Regions | us-east-1, us-east-2 | eu-west-1, eu-central-1 |
| Health check (step 2) | `<ue1 id>`, alarm on `ue1-main-alarms` | `<ew1 id>`, alarm relayed to `ew1-main-alarms` and `ec1-main-alarms` |
| Database | `ue2-prod-main-db` (`ue1-prod-main-db`), key `alias/ue2-main` | `ec1-prod-main-db` (`ew1-prod-main-db`), key `alias/ec1-main` |
| Cache | `ue2-prod-cache` (`ue1-prod-cache`), `redis-auth/ue2/prod-cache` | `ec1-prod-cache` (`ew1-prod-cache`), `redis-auth/ec1/prod-cache` |
| Cluster | `ue2-main` | `ec1-main` |
| Step 6 branch | `stacks/orgs/fnx/prod/us-east-2/components/compute.yaml` | `stacks/orgs/fnx/prod/eu-central-1/components/compute.yaml` |
| State, its replica | `fnx-terraform-state` (us-east-1), `fnx-terraform-state-replica` (us-east-2) | `fnx-ew1-terraform-state` (eu-west-1), `fnx-ew1-terraform-state-replica` (eu-central-1) |
| Backup copies | `ue1-backup-replica` (us-east-2) | `ew1-backup-replica` (eu-central-1) |
| User migration, pools | `ue2-cognito-user-migration`; `<ue1 pool id>`, `<ue2 pool id>` | `ec1-cognito-user-migration`; `<ew1 pool id>`, `<ec1 pool id>` |
| Domain | `api.<domain>` | `api.<EU apex>` |

What differs beyond the names:

- **GDPR.** No step copies EU data, state or backups out of the EU: every database, cache,
  backup, state and Cognito command runs in eu-west-1 or eu-central-1. The one us-east-1
  interaction is Route 53 (step 2): its API and the health check alarms are there for every
  pair, and that is configuration and metadata only, no personal data. `dr-pair.py` refuses an
  EU pair whose standby, backup copy or state replica is outside the EU.
- **State (step 6).** An eu-west-1 outage takes `fnx-ew1-root`'s bucket with it;
  `TFSTATE_SOURCE=replica` reads `fnx-ew1-terraform-state-replica` in eu-central-1 instead (see
  [State during a us-east-1 outage](#state-during-a-us-east-1-outage), EU paragraph). The US
  state bucket and replica are never involved.
- **Step 6** for `fnx-ec1-prod`: `eks-backend-services/main` is `metadata.enabled: false` while
  warm (its database is a read-only replica until promoted). After steps 3 and 4, on a branch,
  set the table's inputs with the EU names (`database_secret_arn` from
  `aws rds describe-db-instances --db-instance-identifier ec1-prod-main-db --region eu-central-1
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text`, `database_name`
  `productionapp`), then:

  ```bash
  export TFSTATE_SOURCE=replica          # !terraform.state reads go to the eu-central-1 replica
  rm -f components/terraform/eks-backend-services/backend.tf.json
  atmos terraform deploy eks-backend-services/main -s fnx-ec1-prod --auto-generate-backend-file=false
  ```

- **Step 7.** Neither EU stack has `rds/data`; any other recovery point is restored from
  `ew1-backup-replica` in eu-central-1, never from a US vault.
- **Warm sizes**, scaled as above with the EU names: `workers` 3/6/12, `monitoring` 2/3/4,
  `memory-optimized` 2/3/6 on `ec1-main`; `ec1-prod-main-db` to `db.r5.xlarge` and
  `ec1-prod-cache` to 3 nodes, in eu-central-1, if the load needs it.
- **Auth.** `ec1-cognito-user-migration` copies users from `fnx-ew1-prod`'s pool while eu-west-1's
  Cognito answers; during an eu-west-1 outage, bulk-import with `SRC=eu-west-1 DST=eu-central-1`
  ([Auth during failover](#auth-during-failover)): the export, `users.csv` and their bucket and key
  are in eu-central-1.
- **Reconcile and failback** as above with the EU names: the failback's literal
  `replicate_source_db` on `fnx-ew1-prod` is
  `arn:aws:rds:eu-central-1:{{ .settings.environment.account_id }}:db:ec1-prod-main-db`, and
  `fnx-ec1-prod`'s is restored to `!terraform.state rds/main fnx-ew1-prod .instance_arn` (with the
  warm `db.r5.large`); step 6 removes an added replica from `ec1-prod-cache` in eu-central-1.

#### Auth during failover

Written for the US pair; the EU pair is the same with `fnx-ew1-prod`/`fnx-ec1-prod`, eu-west-1/
eu-central-1 and `ec1-cognito-user-migration` ([EU failover](#eu-failover)). AWS has no cross-region user pools, so `fnx-ue2-prod` runs its own `cognito/main` (settings shared
with `fnx-ue1-prod`'s through `catalog/cognito/prod`), and its `apigateway/main` authorizer uses
that pool only (owner decision 2026-10-07). `/api`, the only authorized route, is disabled in both
regions today; the authorizer is wired for when it returns. On failover nothing is switched:

- A token issued by one pool is valid only at that region's authorizer: every user signs in again.
- A user the us-east-2 pool does not have yet is copied in by its user-migration trigger
  ([AWS](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-migrate-user.html)),
  `ue2-cognito-user-migration`. On a password sign-in (`UserMigration_Authentication`) it checks the
  password against `fnx-ue1-prod`'s pool (`AdminInitiateAuth` with its `dr-migration` client) and
  returns the user's attributes; Cognito creates the user `RESET_REQUIRED` (never `CONFIRMED`), and
  only for a user with a verified email (the pool has no SMS, so a phone alone is refused). On a
  forgot-password (`UserMigration_ForgotPassword`) it reads the user (`AdminGetUser`), and Cognito
  sends the reset code to the verified email. Its role may call only those two actions, on that
  pool's ARN.
- The trigger runs only for a password sign-in (`ADMIN_USER_PASSWORD_AUTH` with the `api` client,
  which allows it in us-east-2 only) or a forgot-password, never for SRP: the backend signs in a
  user us-east-2 does not know with `AdminInitiateAuth` `ADMIN_USER_PASSWORD_AUTH` (on
  `UserNotFoundException` from SRP, retry that way).
- MFA is mandatory in both pools and TOTP secrets do not migrate. A `CONFIRMED` user would get
  `MFA_SETUP` on first sign-in, so anyone with only the password could enrol their own
  authenticator. A migrated user is therefore reset first: the first us-east-2 sign-in fails with
  `PasswordResetRequiredException`, the user finishes forgot-password with the code sent to the
  verified contact, and only then enrols an authenticator (`MFA_SETUP`). The app must handle
  `PasswordResetRequiredException` during failover (send the user to forgot-password).
- **The limit:** the trigger needs us-east-1's Cognito to answer. During a us-east-1 outage a user
  never migrated before it cannot sign in to us-east-2 until they are imported (below). Users
  migrated earlier and finished the reset and MFA enrolment sign in normally.
- A migrated user is a snapshot: a later password change, disable or attribute change in
  `fnx-ue1-prod`'s pool does not reach us-east-2. To
  re-sync one user, delete it in us-east-2 (`aws cognito-idp admin-delete-user --region us-east-2
  --user-pool-id <ue2 pool id> --username <email>`); the next sign-in migrates it again.

- During failover, and after each monthly export, reconcile: compare the us-east-2 users with the
  latest export (`users-export-<date>.json`: `Enabled`, `UserStatus`, absence) and run
  `aws cognito-idp admin-disable-user --region us-east-2` (or `admin-delete-user`) on any user
  whose `fnx-ue1-prod` copy is disabled, not `CONFIRMED`/`RESET_REQUIRED`, or gone: a migrated user
  is a snapshot and would otherwise keep working there.

Do not pre-migrate users with a shadow sign-in: each would sit in us-east-2 with no MFA device until
a reset. Compare the two pools' sizes monthly, with `dr-status`
(`<ue1 pool id>`/`<ue2 pool id>`: `cognito/main`'s `user_pool_id` output in each stack):

```bash
aws cognito-idp describe-user-pool --region us-east-1 --user-pool-id <ue1 pool id> --query 'UserPool.EstimatedNumberOfUsers'
aws cognito-idp describe-user-pool --region us-east-2 --user-pool-id <ue2 pool id> --query 'UserPool.EstimatedNumberOfUsers'
```

**Bulk import** (an operator step, before or during an outage) puts the users not yet migrated into
us-east-2 with a Cognito CSV import job
([AWS](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-using-import-tool.html)).
Passwords cannot be exported: imported users are `RESET_REQUIRED` and reset by email before their
first sign-in, and an imported user no longer runs the trigger (it exists). So import during an
outage only, or for users who accept a reset. The export needs us-east-1's Cognito, so take it
monthly with the coverage check and keep it outside us-east-1 (it is personal data: encrypted
storage in us-east-2, access as for the database; the EU pair's in eu-central-1, never outside the EU):

```bash
set -o pipefail
# US pair. EU pair: SRC=eu-west-1 DST=eu-central-1, the <ew1>/<ec1> pool ids, and a bucket and
# key in eu-central-1: EU personal data never leaves the EU.
SRC=us-east-1; DST=us-east-2; SRC_POOL=<ue1 pool id>; DST_POOL=<ue2 pool id>
OBJ=s3://<bucket in DST>/<prefix>; KMS=<kms key id in DST>
EXPORT="$OBJ/users-export-$(date -u +%Y%m%d).json"
# 1. Export ($SRC healthy), streamed to an SSE-KMS object in $DST, never to a local file,
#    then check it holds the pool's users (the pool count is an estimate: expect a close match).
aws cognito-idp list-users --region "$SRC" --user-pool-id "$SRC_POOL" --output json |
  aws s3 cp - "$EXPORT" --sse aws:kms --sse-kms-key-id "$KMS" --region "$DST"
aws s3 cp "$EXPORT" - --region "$DST" | jq '.Users | length'
aws cognito-idp describe-user-pool --region "$SRC" --user-pool-id "$SRC_POOL" --query 'UserPool.EstimatedNumberOfUsers'
# 2. users.csv from the export, with the header $DST expects and only the users the Lambda would
#    migrate (enabled, CONFIRMED or RESET_REQUIRED), again straight to SSE-KMS S3.
HEADER=$(aws cognito-idp get-csv-header --region "$DST" --user-pool-id "$DST_POOL" --query CSVHeader --output text | tr '\t' ',')
aws s3 cp "$EXPORT" - --region "$DST" | jq -r --arg h "$HEADER" '
  ($h | split(",")) as $cols | $h,
  (.Users[] | select(.Enabled == true and (.UserStatus == "CONFIRMED" or .UserStatus == "RESET_REQUIRED"))
   | (.Attributes | map({(.Name): .Value}) | add) as $a
   | ($a + {"cognito:username": $a.email, "cognito:mfa_enabled": "false"}) as $row
   | [$cols[] | $row[.] // ""] | @csv)' |
  aws s3 cp - "$OBJ/users.csv" --sse aws:kms --sse-kms-key-id "$KMS" --region "$DST"
# 3. Import with a role that lets Cognito write the job's CloudWatch logs
#    (trust cognito-idp.amazonaws.com; logs:CreateLogGroup/CreateLogStream/DescribeLogStreams/PutLogEvents).
aws cognito-idp create-user-import-job --region "$DST" --user-pool-id "$DST_POOL" \
  --job-name "dr-$(date -u +%Y%m%d%H%M)" --cloud-watch-logs-role-arn <role arn>
# A presigned PUT needs a Content-Length (no chunked upload) and the header Cognito's URL is signed with.
aws s3 cp "$OBJ/users.csv" - --region "$DST" |
  curl -sf -X PUT --data-binary @- -H 'Content-Type:' -H 'x-amz-server-side-encryption: aws:kms' "<PreSignedUrl from above>"
aws cognito-idp start-user-import-job --region "$DST" --user-pool-id "$DST_POOL" --job-id <JobId>
aws cognito-idp describe-user-import-job --region "$DST" --user-pool-id "$DST_POOL" --job-id <JobId>
```

The bucket holds personal data: it needs SSE-KMS by default and a lifecycle expiry (no stack here
provides one yet, so create or pick it first).

Leave out users already in the standby's pool (`list-users` there): an existing username fails its row.

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
   `replicate_source_db: !terraform.state rds/main fnx-ue1-prod .instance_arn` on a branch, with
   the warm `instance_class: db.r5.large` if failover resized it (the `-replace` creates the
   instance at the branch's class), and
   `atmos terraform apply rds/main -s fnx-ue2-prod -- -replace=aws_db_instance.main`; merge.
6. Back to warm: a PR reverting reconciliation steps 2 and 3, and the desired sizes Terraform
   ignores by CLI (`update-nodegroup-config ... --scaling-config minSize=2,desiredSize=2,maxSize=12`
   for `workers`, `0/0/<max>` for the others). If failover added a cache replica, remove it
   (`aws elasticache decrease-replica-count --replication-group-id ue2-prod-cache
   --new-replica-count 1 --apply-immediately --region us-east-2`): back to the warm 2 nodes
   `num_cache_nodes` still holds.
7. Auth: once DNS is back on us-east-1, users sign in to `fnx-ue1-prod`'s pool again (us-east-2
   tokens are not valid there). Nothing flows back from us-east-2: a password a user changed or
   reset there is not us-east-1's, so they reset it again in us-east-1 (forgot-password), and a
   user an administrator created in us-east-2 is created again in us-east-1. List them with
   `aws cognito-idp list-users --region us-east-2 --user-pool-id <ue2 pool id> --filter
   'cognito:user_status = "RESET_REQUIRED"'` and by `UserCreateDate` after the failover. The
   us-east-2 users do not stay: delete the migrated ones (`admin-delete-user`), so stale passwords
   and statuses do not carry into the next failover; they migrate again then
   ([Auth during failover](#auth-during-failover)).
8. Re-enable CD: `gh workflow enable terraform-cd.yml`.

## Deploys green, does not serve

`cognito/main` has no users or identity provider, so `/api` rejects every request; `apigateway` `/` is a `MOCK`
liveness endpoint by design.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` cannot assume `<role_prefix>-*-role` (`fnx-terraform-backend-*-role`) | Run `backend-cold-start`, or add the caller's role ARN to that stage's `access_roles` in `stacks/orgs/fnx/root/us-east-1.yaml` |
| CI plan: AccessDenied on `PutObject` at `workspace new` | Read roles cannot create a workspace; the instance's first deploy does |
| `Error acquiring the state lock` | Another run holds it; `list-locks`, then `force-unlock` if abandoned |
| `!terraform.state` returns nothing | The referenced instance is not deployed in that stack yet; deploy in layer order |
| A string input rejects a `!terraform.state` value as an object | The output is a JSON string (a `*_policy`); end the read with `\| tojson` |
| ACM validation times out after 45 minutes | The stack's domain is not delegated; see [Deploying a stack](#deploying-a-stack) |
