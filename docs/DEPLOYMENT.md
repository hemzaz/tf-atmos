# Deployment Guide

How to take one of the three stacks (`fnx-dev-testenv-01`, `fnx-staging-staging-01`,
`fnx-prod-production`) from nothing to deployed.

## Manual prerequisites before first apply

The stack configuration still contains placeholders. Replace every item below before running
`apply` or `deploy` against a real account.

| Input | Where | Placeholder today |
|-------|-------|-------------------|
| Workload account IDs | `settings.environment.account_id` in `stacks/orgs/fnx/{dev,staging,prod}/_defaults.yaml`; `settings.environment.aws_account_id` in `staging-01.yaml` and `production.yaml` | `123456789012` |
| Dev account ID | `testenv-01.yaml` reads it from the `AWS_ACCOUNT_ID` environment variable | export `AWS_ACCOUNT_ID` before running Atmos for dev |
| Management account ID | `settings.environment.management_account_id` in `stacks/orgs/fnx/_defaults.yaml` (backend role ARN, IAM trust) | `123456789012` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` | `o-xxxxxxxxxx` |
| Domains | `settings.environment.domain_name` in each stack's `components/globals.yaml`: the one source every dns zone/record, acm domain/SAN and apigateway custom domain is derived from (zone ids come from the dns instances' `zone_ids` output). The stack wires `services.<d>` and `data.services.<d>` delegation itself (NS records); only `<d>` needs delegating from its parent, see below | `fnx.example.com` (prod), `staging.fnx.example.com`, `dev.fnx.example.com` |
| Alert recipients | `alarm_email_subscriptions` on the monitoring instances, and notification lists in `components/globals.yaml`; every address must confirm its SNS subscription | `*@example.com` |
| Prod alarm SNS topic ARNs | Prod alarms that must reach an existing paging/on-call topic, e.g. `rds`'s `sns_topic_arn` | not set |
| State backend | One bucket, `fnx-terraform-state`, in the management account with five access roles split by stage: `fnx-terraform-backend-role` / `fnx-terraform-backend-read-role` (read/write / read-only, dev and staging objects, trust the dev/staging CI apply / plan roles), `fnx-terraform-backend-prod-role` / `fnx-terraform-backend-prod-read-role` (prod objects, trust only prod's apply / plan role) and `fnx-terraform-backend-core-role` (`fnx-core-root` objects, trusts only the administrator who applies `backend/main`). Every stack's backend config assumes one of them, so they must exist before any other stack's first `terraform init` | created once by `backend/main` in stack `fnx-core-root` (cold start, [below](#bootstrap-the-state-backend)); its trusted role ARNs carry the placeholder account IDs |
| GitHub Environments | None. CD uses no environment (Cloud Posse model): the apply roles trust the default-branch ref, and `terraform-cd.yml` derives each stack's apply role ARN from its `iam/ci`. There is no manual approval step - see [below](#bootstrap-the-state-backend) | n/a |
| Default-branch protection | The deploy gate: every merge to the default branch applies every affected stack, production included. Require pull requests and reviews on it | none |
| GitHub repo variables | `AWS_PLAN_ROLE_ARN` (read-only plan role for PR plans, dev/staging drift detection, DR checks — a dev or staging `iam/ci` `ci_plan_role_arn`); `AWS_PROD_PLAN_ROLE_ARN` (production's `iam/ci` `ci_plan_role_arn`, for prod plans on push to master and prod drift); optional `ATMOS_VERSION`, `AWS_REGION` | none |
| OIDC trust | Deploy (apply) role: `sub = repo:<org>/<repo>:ref:refs/heads/<default branch>` only (`iam/ci` `ci_apply_role_trusted_github_repos`, Cloud Posse's branch-pinned `trusted_github_repos`). Plan role: `sub = repo:<org>/<repo>:pull_request` and `...:ref:refs/heads/<default branch>`; production's plan role only the default-branch sub (prod is planned from master, never from a PR). Both: `aud = sts.amazonaws.com` | none |
| Deploy marker tags | One `deployed/<stack>` tag per stack, so CD knows what's already live | none |
| Lambda deployment packages | `s3_bucket`/`s3_key` on every `lambda/*` instance in each stack's `components/services.yaml`. The buckets (`fnx-lambda-artifacts`, `fnx-staging-lambda-artifacts`, `fnx-production-lambda-artifacts`) must exist and hold the named key **before** the first apply — `aws_lambda_function` fails at apply without a package, and no static gate catches it | `<function>/latest.zip`, not uploaded |
| Existing state | If state exists under an older bucket/key layout, migrate it first (below) | n/a |

```bash
# Bootstrap the deploy tags once per stack
git tag deployed/fnx-dev-testenv-01 <last-deployed-sha>
git push origin deployed/fnx-dev-testenv-01
```

### Migrating existing state

State lives in one S3 bucket, `fnx-terraform-state`, with native lockfiles and no DynamoDB table.

```bash
atmos describe component vpc/main -s fnx-dev-testenv-01   # .backend (bucket, workspace_key_prefix), .workspace
```

If an instance already has state under a different bucket/key, copy it to the new location first,
or Terraform will plan to recreate the resources:

```bash
aws s3 cp s3://<old-bucket>/<old-key> ./old.tfstate
atmos terraform state push vpc/main -s fnx-dev-testenv-01 ./old.tfstate
atmos terraform plan vpc/main -s fnx-dev-testenv-01   # expect no resource replacements
```

The `network/*` instances use the `dns` root module; state from a different module won't match its
addresses, so import the existing zones instead (`atmos workflow import -f import -s <stack>`).

This section is about moving state to a different **bucket or key**. Moving a resource to a
different **address** — a rename, a module move, a `count`-to-`for_each` change — is
[Moving resources in state](./OPERATIONS.md#moving-resources-in-state).

## Bootstrap the state backend

There is one state backend for every stack: bucket `fnx-terraform-state`, its KMS key and five
stage-split access roles, managed by the only `backend` instance, `backend/main` in the management account's
stack `fnx-core-root` (`stacks/orgs/fnx/core/eu-west-2/root.yaml`). Workload stacks have no
backend instance. Create it once, first, with management-account administrator credentials:

```bash
atmos workflow backend-cold-start -f bootstrap             # once: local-state apply, then migrate into the bucket
atmos workflow backend-only -f bootstrap                   # later changes to the backend
atmos workflow verify -f bootstrap                         # backend describe + outputs
atmos workflow full -f bootstrap -s fnx-dev-testenv-01     # then per stack: IAM (CI roles), VPCs
```

The cold start and the import path for a bucket that already exists are in
[components/terraform/backend/README.md](../components/terraform/backend/README.md#bootstrap).

How the stacks reach it (`stacks/orgs/fnx/_defaults.yaml`):

| Who | Role assumed by the stack backend | Trusts | Locking |
|-----|-----------------------------------|--------|---------|
| CI plans of dev/staging: `TFSTATE_ACCESS=read` | `fnx-terraform-backend-read-role` (read-only; objects `*/fnx-dev-*`, `*/fnx-staging-*`) | the dev and staging `iam/ci` plan roles | `-lock=false` |
| CI deploys (`terraform-cd.yml`) of dev/staging, local runs | `fnx-terraform-backend-role` (read/write; objects `*/fnx-dev-*`, `*/fnx-staging-*`) | the dev and staging `iam/ci` apply roles, and the administrator who applied `backend/main` | `.tflock`, `-lock-timeout=10m` in CD |
| CI plans of prod (push to master, drift, DR): `TFSTATE_ACCESS=read` in a stage-`prod` stack | `fnx-terraform-backend-prod-read-role` (read-only; objects `*/fnx-prod-*`) | only prod's `iam/ci` plan role (`AWS_PROD_PLAN_ROLE_ARN`, master subject only), and the administrator | `-lock=false` |
| CI deploys of prod, local runs | `fnx-terraform-backend-prod-role` (read/write; objects `*/fnx-prod-*`) | only prod's `iam/ci` apply role, and the administrator | `.tflock`, `-lock-timeout=10m` in CD |
| `fnx-core-root` (the backend itself), read or write | `fnx-terraform-backend-core-role` (read/write; objects `*/fnx-core-*`) | only the administrator who applies `backend/main` - no CI role | `.tflock` |

What this does and does not protect:

- **PR code cannot read production state contents.** A `pull_request` workflow gets an OIDC token
  whose sub is `repo:<org>/<repo>:pull_request`, which only the dev/staging plan roles trust; they
  can assume only `fnx-terraform-backend-read-role`, whose `GetObject` is limited to
  `*/fnx-dev-*` and `*/fnx-staging-*`. The prod plan role and every apply role trust the
  default-branch ref alone, so this holds even if the PR edits the workflow files.
- **It can see key names.** `s3:ListBucket` (and, for the DR checks, `s3:ListBucketVersions`) is
  not prefix-scoped - Terraform lists `<component>/` to find workspaces - so every read role sees
  key *names* (component and stack/instance names) across stages; see
  [the backend README](../components/terraform/backend/README.md#deployed-as).
- **Merged code is trusted everywhere.** Once merged, code runs with the default-branch sub, which
  the prod plan role and every apply role (AdministratorAccess) trust. The default branch's
  protection is the only gate.
- **Writes are split the same way.** A dev/staging apply role cannot touch prod or core state,
  prod's apply role cannot touch dev/staging or core state, and no CI role can read or write
  `fnx-core-root` state. `check-state-keys.py` (`validate-all`, `lint`) keeps every instance's
  state key inside its stage's prefix, which these patterns rely on.

`iam/ci` gets `sts:AssumeRole` on its own stage's read role (plan) and write role (apply) only,
naming them by the same convention as the stack backend (`stacks/orgs/fnx/_defaults.yaml`) rather
than reading `backend/main`'s state, which no CI role can read. The backend trusts the CI roles by
their names (`<tenant>-<account>-<environment>-ci-plan` / `-apply`), listed in `root.yaml`: a new
stack's CI roles must be added there. Anyone else who runs Terraform against a stack (an operator's
SSO role) must be added to that stage's `access_roles` entries too.

Production is planned from master only: its plan role does not trust the `pull_request` OIDC
subject, and `terraform-ci.yml` plans prod instances on push to master instead of on the PR
(`settings.github.pull_request_plans_enabled: false` in `stacks/orgs/fnx/prod/_defaults.yaml`),
with `AWS_PROD_PLAN_ROLE_ARN`.

The CI apply role (`<prefix>-apply`) is enabled in every stack with `AdministratorAccess` (it
deploys every component, `iam` included; it is also the EKS ClusterAdmin access entry). Its trust
is Cloud Posse's branch-pinned model
([`github-assume-role-policy.mixin.tf`](https://github.com/cloudposse/terraform-aws-components/blob/main/modules/account-map/modules/team-assume-role-policy/github-assume-role-policy.mixin.tf)):
only `sub = repo:<org>/<repo>:ref:refs/heads/<default branch>`; `pull_request`, `environment:`
and wildcard subjects are rejected by validation. `terraform-cd.yml` uses no GitHub Environment.
**There is no manual approval before a deploy, production included: every merge to the default
branch that affects a stack applies it.** Review happens on the pull request (with the plans CI
posts there; prod's plan runs on the push to master), and merging is the approval.

## Deploy the stack

`workflows/deploy-full-stack.yaml` deploys in layers. Each layer selects instances by root module
(`metadata.component`) and, where one instance of a type reads another, by instance name
(`atmos_component`). It plans them, shows the plans, asks for confirmation, then applies exactly
those planfiles (`terraform deploy --from-plan`).

| Layer | Workflow | Selects |
|-------|----------|---------|
| backend | `deploy-backend` | `backend` (only `fnx-core-root` has one) |
| iam | `deploy-iam` | `iam` (`iam/ci` depends on `backend/main` in `fnx-core-root`) |
| kms | `deploy-kms` | `kms` |
| networking | `deploy-networking` | `vpc` |
| connectivity | `deploy-connectivity` | `securitygroup`, `network` (VPC peering), `ec2/bastion` |
| security | `deploy-security` | `secretsmanager`, `guardduty`, `securityhub`, `cloudtrail`, `awsconfig`, `cognito` |
| security-monitoring | `deploy-security-monitoring` | `security-monitoring` (reads GuardDuty and Security Hub) |
| compute | `deploy-compute` | `eks`, `ecs`, `lambda`, `ec2` other than `ec2/bastion` |
| platform | `deploy-platform` | `external-secrets` |
| data | `deploy-data` | `rds`, `elasticache`, `backup` |
| dns-zones | `deploy-dns-zones` | `network/services` (its `services` zone, and its `data` zone delegated from it by `parent_zone`) |
| dns | `deploy-dns` | the other `dns` instances (after data: records point at RDS endpoints; `network/main` writes the NS record delegating `services.<d>` from `network/services`' name servers) |
| certificates | `deploy-certificates` | `acm` (after dns: validates in its `zone_ids`) |
| addons | `deploy-addons` | `eks-addons` (after dns: reads its `zone_ids`) |
| services | `deploy-services` | `apigateway` (reads `lambda` and `cognito`), `eks-backend-services` |
| monitoring | `deploy-monitoring` | `monitoring`, `cost-optimization` |

A layer plans all of its instances before it applies any of them. On a first deploy, an instance
that reads another's state (`!terraform.state` / `!terraform.output`) would find none, so it must
be in a **later** layer than the instance it reads. A dependency that is only declared in
`dependencies.components` may share a layer, because Atmos applies a layer in dependency order.
Every enabled, non-abstract instance must be in exactly one layer. `validate-all` enforces all of
this (`workflows/scripts/common/check-deploy-layers.py`), and applies the same read rule to
`deploy-app` in `deploy-application.yaml` and `full` in `bootstrap.yaml`. A new root module, or a
new read of an instance in the same or a later layer, needs a layer change here. A layer whose
root modules no stack uses yet plans nothing ("No components matched").

```bash
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01                 # all layers
atmos workflow deploy-networking -f deploy-full-stack -s fnx-dev-testenv-01      # one layer
```

The `kms` layer applies `kms/main`, which is enabled in dev, staging, prod and the local sandbox
(secretsmanager, EC2, EKS, RDS and others read its key via `!terraform.state`). A stack without an
enabled `kms` component (`fnx-local-localemu`) plans nothing there, and the prompt just asks to
continue.

Other ways to deploy (`apply-environment` plans every instance before applying any, so it only
works once every instance it reads has state; use `deploy-full-stack` for a stack's first deploy):

```bash
atmos workflow apply -f apply-environment -s <stack>      # whole stack: plan, one confirmation, deploy (not a first deploy)
atmos terraform plan <component> -s <stack>               # one instance
atmos terraform deploy <component> -s <stack>              # one instance: plan + apply
atmos workflow component -f deploy-application -s <stack> # one instance, name entered at a prompt
atmos workflow deploy-app -f deploy-application -s <stack> # secrets, Cognito, Lambda, ECS, then API Gateway and monitoring
atmos workflow hot-deploy -f deploy-application -s <stack> # Cognito, Lambda, API Gateway: no plan review
```

`deploy-app` and `hot-deploy` assume the instances they read are already applied: `kms/main`,
`vpc/*`, `eks/*` (where present), `acm/*` and the dns zones `network/main` and `network/services`
(deploy-full-stack layers backend through certificates).

Before `deploy-certificates` (manual prerequisite): delegate each stack's top-level `<d>` (`network/main`'s `main` zone, e.g. `dev.fnx.example.com`) from its parent domain at the registrar/parent zone using that zone's name servers (`zone_name_servers.main`), or ACM validation times out after 45 minutes.

`hot-deploy` is the one deliberate exception to reviewing a saved plan before applying it. It is
a fast path that runs `terraform deploy` (plan and auto-approve per instance, in dependency order)
without a confirmation. Use `deploy-app` when the change should be reviewed.

There are no `metadata.enabled: false` instances left in `stacks/orgs/` (see
[Components](../README.md#components)). No stack deploys `idp-platform`.

## Deploying a stack template

`stacks/catalog/templates/` has five opt-in templates (`web-application`, `microservices-platform`,
`serverless-api`, `data-pipeline`, `batch-processing`); none of the three existing stacks imports
one today. A stack uses one by importing it and setting its required variables — see
[stacks/README.md](../stacks/README.md#stack-templates). Then:

```bash
atmos workflow deploy -f deploy-template -s <stack>              # choose, plan, confirm, deploy, verify
atmos workflow deploy-serverless -f deploy-template -s <stack>   # quick deploy, no confirmation
atmos workflow deploy-parallel -f deploy-template -s <stack>     # independent components concurrently
```

A template deploys only if every `component:` it names resolves to a directory under
`components/terraform/`; otherwise `deploy-template` cannot find that component. As of this
writing only `microservices-platform` meets that bar — check
`git grep -n 'component:' stacks/catalog/templates/<template>.yaml` against
`components/terraform/` for the current state of the other four, since it changes as their
missing components land.

## CI across several AWS accounts

The prerequisites above assume the CI roles live in the account being deployed. If you run more
than one account, put the OIDC provider and the CI roles in a single hub account instead and reach
the workload accounts by `sts:AssumeRole`. An account can hold only one OIDC provider for
`token.actions.githubusercontent.com`, so a provider per stack collides the moment two stacks share
an account; a provider is also account-local, so a spoke cannot federate against the hub's.

Opt-in templates: `catalog/iam/oidc-hub` and `catalog/iam/oidc-spoke` (both abstract — a stack must
`import` **and** `metadata.inherits` them). Worked example, including the assume-spoke policy and
the bootstrap order: [examples/github-oidc-hub-spoke](../examples/github-oidc-hub-spoke/README.md).

## Deploy through CI/CD

After the GitHub prerequisites above are in place:

- **Pull requests** (`terraform-ci.yml`): lint, validation, plan-sweep, a security gate (fails only
  on new HIGH/CRITICAL Trivy/Checkov findings not already in `.trivyignore.yaml`/`.checkov.baseline`),
  `terraform test` for components with a `tests/` directory that the change affects, and a plan of
  every affected component with the read-only plan role, posted as PR comments. See the
  [CI/CD table](../README.md#cicd) for the full job list, including the `emulator.yml` LocalEmu
  lane, which also runs on PRs.
- **Merges to the default branch** (`terraform-cd.yml`): for each stack in turn (dev, staging,
  prod), runs `atmos terraform deploy --affected` against the stack's `deployed/<stack>` tag with
  that stack's `iam/ci` apply role (no GitHub Environment, no manual approval), then moves the tag.
- **Manual runs**: `terraform-cd.yml` can plan or deploy one stack (optionally one component) from
  the default branch.

Destroy is not exposed in CI; use `atmos workflow destroy -f destroy-environment` locally.

## Applies clean, does not serve traffic

These are deliberate, not defects. Each one will `apply` green and then not do the thing its
name suggests, because the missing piece is a real-world consumer this repo does not manage.
Nothing here blocks a deploy; all of it blocks a working system.

| What | Where | Why it is empty | To make it work |
|------|-------|-----------------|-----------------|
| Prod Redis reachable by nothing | `elasticache/main` in `stacks/orgs/fnx/prod/eu-west-2/production/components/services.yaml` — `allowed_security_group_ids: []`, `allowed_cidr_blocks: []` | Fail-closed on purpose. The `ecs` component is cluster-only (no service, no security group output) and `securitygroup` is instantiated nowhere, so there is no consumer group to name. | Add the consuming service's security group id once one exists. The component exports `security_group_id` for the reverse direction. `0.0.0.0/0` is rejected by validation. |
| Cognito pool with no way in | `cognito/main` in every stack | The pool has clients but no users and no federated identity provider. `/api` sits behind `COGNITO_USER_POOLS`, so every request is rejected. | Create users, or configure a federated IdP — both need real credentials that do not belong in this repo. |
| `/` returns a canned 200 | `apigateway/main`, `apigateway/data` — the `/` method stays `MOCK` | Intentional. `/` is a liveness endpoint and a canned 200 is the correct answer for one. | Nothing. `/api` and `/data` are the real Lambda-backed routes. |
| ~~Lambda has no deployment package~~ **fixed** | was: every `lambda/*` instance | **Confirmed by applying it**: `aws_lambda_function` rejects `one of filename,image_uri,s3_bucket must be specified`, so all 6 org-stack lambdas were uncreatable while every static gate reported green. Each now names an S3 object (below). | Nothing in config. Build the package and upload it to the bucket/key each instance names. |
| CI never plans anything | `.github/workflows/terraform-ci.yml` gates the plan job on `vars.AWS_PLAN_ROLE_ARN != ''` | The variable is unset, so every run reports Plan SKIPPED. | Set `AWS_PLAN_ROLE_ARN` to a read-only role (see the prerequisites table). Highest-value change here: it needs no apply, and it would have caught the Lambda VPC egress defect fixed in v1.1.0. |

## Verify and rollback

```bash
atmos workflow verify -f bootstrap -s <stack>
atmos terraform output eks/main -s <stack>
atmos workflow drift-detection -f drift-detection -s <stack>   # should report no changes
```

- **Configuration change**: revert the commit and merge; CD redeploys the affected components.
- **State**: the bucket is versioned — see [Operations Guide](./OPERATIONS.md#state-recovery).
- **Whole stack**: `atmos workflow destroy -f destroy-environment` (type the stack name to confirm)
  removes every component in reverse dependency order.

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` fails to assume `fnx-terraform-backend[-prod\|-core][-read]-role` | Backend not bootstrapped yet (`backend-cold-start`), or the caller's role ARN is not in that stage's entry of `backend/main`'s `access_roles` in `fnx-core-root` (`fnx-core-root` itself: only the administrator who applied `backend/main`) — see [Bootstrap the state backend](#bootstrap-the-state-backend) |
| A CI plan fails creating the workspace (`workspace new`, AccessDenied on `PutObject`) | The read-only state role cannot create a workspace's first (empty) state object; the instance's first deploy creates it |
| `Error acquiring the state lock` | Another run holds the lockfile; see [Operations Guide](./OPERATIONS.md#state-locks) |
| `!terraform.state` returns nothing | Referenced component hasn't been deployed in that stack yet; deploy in layer order |
| Plan wants to recreate existing resources | State wasn't migrated to the new backend layout; see above |

See the [Operations Guide](./OPERATIONS.md) for day-2 tasks.
