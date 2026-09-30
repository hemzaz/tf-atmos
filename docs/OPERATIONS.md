# Operations

Bootstrap, deploy and run the stacks; the developer side is in the [README](../README.md).
Workflows shown with `-s <stack>` take the flag; those shown with `STACK=<stack>` read the
variable (or prompt).

## First-deploy inputs

The stacks hold placeholders. Replace them before any apply against a real account.

| Input | Where |
|-------|-------|
| Workload account IDs | `settings.environment.account_id` in `stacks/orgs/fnx/{dev,staging,prod}/_defaults.yaml`; `settings.environment.aws_account_id` in `staging-01.yaml` and `production.yaml` (dev reads it from `AWS_ACCOUNT_ID`); the CI role ARNs in `access_roles` of `stacks/orgs/fnx/core/eu-west-2/root.yaml` |
| Management account ID | `settings.environment.management_account_id` in `stacks/orgs/fnx/_defaults.yaml` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` |
| Domains | `settings.environment.domain_name` in each stack's `components/globals.yaml`; every zone, record, certificate and API domain derives from it |
| Alert recipients | `alarm_email_subscriptions` on monitoring instances and the lists in `components/globals.yaml`; each address must confirm its SNS subscription |
| Prod RDS alarm target | `sns_topic_arn` on prod's `rds/main`: unset, so its CloudWatch alarms have no action |
| Lambda packages | `s3_bucket`/`s3_key` of every `lambda/*` instance in `components/services.yaml`; the object must exist before the first apply |
| GitHub | default-branch protection (PR + review), and a tag ruleset letting only GitHub Actions move `refs/tags/deployed/**` (`terraform-cd.yml` relies on both) |
| Deploy tags | one `deployed/<stack>` tag per stack: `git tag deployed/<stack> <sha> && git push origin deployed/<stack>` |

Every workload `account_id` must differ from `management_account_id`. The stage split of state
access below holds only then: a workload stack in the management account puts its
`AdministratorAccess` apply role in the bucket's own account, where it reads and writes every
stage's state without going through the access roles.

## State backend

One bucket, `fnx-terraform-state`, in the management account, with native S3 lockfiles
(`use_lockfile: true`, no DynamoDB). It is `backend/main` in `fnx-core-root`, and every stack's
backend (`stacks/orgs/fnx/_defaults.yaml`) assumes one of its access roles, so it is created first,
with management-account administrator credentials:

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
| `fnx-terraform-backend-prod-read-role` (`prod_read`) | read, prod state | prod's CI plan role |
| `fnx-terraform-backend-prod-role` (`prod_write`) | read/write, prod state | prod's CI apply role |
| `fnx-terraform-backend-core-role` (`core_write`) | read/write, `fnx-core-root` state | none |

- CI plans set `TFSTATE_ACCESS=read` and plan with `-lock=false`; deploys leave it unset.
- Trust is by role ARN, listed in `access_roles` in `root.yaml`. Add a new stack's
  `<tenant>-<account>-<environment>-ci-plan`/`-apply` roles there, and any operator role that
  runs Terraform against a stage.
- `check-state-keys.py` (in `lint` and `validate-all`) keeps every state key inside its stage's
  prefix, which the role patterns rely on. `s3:ListBucket` is bucket-wide, so every role sees key
  names across stages, never contents.
- The CI apply role (`iam/ci`, `AdministratorAccess`) trusts only the default-branch subject
  (`repo:<org>/<repo>:ref:refs/heads/<default branch>`). `terraform-cd.yml` uses no GitHub
  Environment: **every merge deploys, prod included, with no manual approval**. Default-branch
  protection is the gate. PR code gets only the dev/staging plan roles; prod is planned on push
  to master (`pull_request_plans_enabled: false` in `stacks/orgs/fnx/prod/_defaults.yaml`).

## Repository variables

| Variable | Value |
|----------|-------|
| `AWS_PLAN_ROLE_ARN` | a dev or staging `iam/ci` `ci_plan_role_arn`: PR plans, dev/staging drift, DR checks. Unset = AWS jobs skip |
| `AWS_PROD_PLAN_ROLE_ARN` | prod's `iam/ci` `ci_plan_role_arn`: prod plans on master, prod drift |
| `ATMOS_VERSION`, `AWS_REGION` | optional overrides |

CD derives each stack's apply role from its `iam/ci` (`workflows/scripts/common/ci-apply-role-arn.py`).
For CI across several accounts from one OIDC provider, see
[examples/github-oidc-hub-spoke](../examples/github-oidc-hub-spoke/README.md).

## Deploying a stack

After the backend: `atmos workflow full -f bootstrap -s <stack>` (IAM, including the CI roles, and
VPCs) with administrator credentials in the stack's account, since no CI role exists yet; no
stack sets a provider role, so every component runs as the caller. Then `atmos workflow deploy -f deploy-full-stack -s <stack>`. It runs these layers in
order, each planned, confirmed, then applied from the saved plan. Each layer is also its own
workflow (`atmos workflow deploy-<layer> -f deploy-full-stack -s <stack>`):

`backend`, `iam`, `kms`, `networking`, `connectivity`, `security`, `security-monitoring`,
`compute`, `platform`, `data`, `dns-zones`, `dns`, `certificates`, `addons`, `services`,
`monitoring`.

The selection of each layer is in `workflows/deploy-full-stack.yaml`. An instance that reads
another's state must be in a later layer; `check-deploy-layers.py` (validate-all) enforces that
and that every enabled instance is in exactly one layer.

**Before `certificates`: delegate the stack's domain.** ACM validates in `network/main`'s `main`
zone, so its domain must resolve, or validation times out after 45 minutes. Prod's
`fnx.example.com` is delegated at the registrar to prod's `zone_name_servers.main`
(`atmos terraform output network/main -s fnx-prod-production`). Dev's and staging's parent is
that Terraform-managed zone: add an NS record for `dev.`/`staging.fnx.example.com` to prod's
`network/main` `records` (`stacks/orgs/fnx/prod/eu-west-2/production/components/networking.yaml`)
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

Of the stack templates only `microservices-platform` names components that all exist; the others
fail at `deploy-template`. No stack deploys `idp-platform`.

## In-cluster components

`eks-addons`, `external-secrets`, `eks-backend-services` and `alb-controller-ingress-group` talk to
the EKS API through the `kubernetes`/`helm` providers. Every cluster's endpoint is private
(`eks_public_access: false`), so GitHub-hosted runners cannot reach it. Their catalog defaults set
`settings.github.actions_enabled: false`: PR plans, CD (push and dispatch) and drift detection skip
them with a `::notice::`, and `check-cluster-api-ci.py` (lint, validate-all) fails any such instance
in a private-endpoint stack that lacks the flag.

An operator applies them from inside the VPC, e.g. on the stack's `ec2/bastion` (SSH with its
Secrets Manager key, or SSM), after `eks/main` and each instance the component reads:

```bash
atmos terraform deploy <component> -s <stack>   # e.g. eks-addons/main, then eks-backend-services/main
atmos workflow deploy-addons -f deploy-full-stack -s <stack>   # or the layer: platform, addons, services
```

The caller needs the stack's apply permissions and an `eks/main` access entry with
`AmazonEKSClusterAdminPolicy` (`stacks/catalog/eks/defaults.yaml` grants only the CI roles; the
creator gets no implicit admin). CD moving `deployed/<stack>` does not mean these were applied.

## Changing infrastructure

Normal path: a PR (CI plans and comments), then merge (CD deploys). A rename, module move or
`count`/`for_each` change gets a `moved {}` block next to the resource; `atmos terraform state mv`
is the fallback for moves configuration cannot express. A moved-only change must plan
`0 to add, 0 to change, 0 to destroy` in every stack. `moved` cannot help when there is no old
object: an inline attribute promoted to a resource, a `ForceNew` replacement, or an instance
switched to a different root module (import instead).

## Day-2 tasks

| Task | Command |
|------|---------|
| Drift (hourly in CI, [in-cluster components](#in-cluster-components) excluded) | `atmos workflow drift-detection -f drift-detection -s <stack>` |
| Security scan | `atmos workflow security-scan -f lint` (fails on HIGH/CRITICAL); `security-baseline -f lint` rewrites the baselines: review the diff, never use it to force a PR green |
| Security Hub findings | `atmos workflow security-audit -f security-hardening -s <stack>` |
| Compliance | `atmos workflow check -f compliance-check -s <stack>`; `report` writes `compliance-report.md` |
| Hardening | `STACK=<stack> atmos workflow harden -f security-hardening` (plans and applies `cloudtrail`, `awsconfig`, `guardduty`, `securityhub`), `harden-iam` (password policy) |
| Import a resource | `atmos workflow import -f import -s <stack>` |
| List / release locks | `STACK=<stack> atmos workflow list-locks -f state-operations`; `atmos workflow force-unlock -f state-operations -s <stack>` (only when nothing is running) |
| Rotate a Secrets Manager/Kubernetes certificate | `atmos workflow rotate -f rotate-certificate` (ACM certificates are Terraform-managed) |
| Destroy a stack / the backend | `atmos workflow destroy -f destroy-environment` / `-f destroy-backend`; both prompt for the stack name, do not pass `-s` |

Destroying the backend is irreversible: it deletes the bucket and every stack's state in it.

Drift fix: codify an intended manual change in the stack, then `atmos terraform deploy`; otherwise
re-apply; import resources created outside Terraform.

Bastion SSH keys are generated per instance and stored in Secrets Manager at
`ssh-key/<Environment>/<name>`. Read `private_key_openssh`, not `private_key_pem`:
`scripts/certificates/export-ssh-key.sh -r eu-west-2 -s ssh-key/<Environment>/bastion -o bastion.key`.
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
STACK=<stack> atmos workflow dr-failover -f disaster-recovery        # interactive, never from CI
STACK=<stack> atmos workflow dr-failback -f disaster-recovery
```

## Deploys green, does not serve

`cognito/main` has no users or identity provider, so `/api` rejects every request; `apigateway` `/` is a `MOCK`
liveness endpoint by design.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `This repository requires Atmos >= 1.229.0` | Upgrade Atmos |
| `init` cannot assume `fnx-terraform-backend-*-role` | Run `backend-cold-start`, or add the caller's role ARN to that stage's `access_roles` in `root.yaml` |
| CI plan: AccessDenied on `PutObject` at `workspace new` | Read roles cannot create a workspace; the instance's first deploy does |
| `Error acquiring the state lock` | Another run holds it; `list-locks`, then `force-unlock` if abandoned |
| `!terraform.state` returns nothing | The referenced instance is not deployed in that stack yet; deploy in layer order |
| ACM validation times out after 45 minutes | The stack's domain is not delegated; see [Deploying a stack](#deploying-a-stack) |
