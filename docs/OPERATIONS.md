# Operations

Bootstrap, deploy and run the stacks; the developer side is in the [README](../README.md).
Workflows shown with `-s <stack>` take the flag; those shown with `STACK=<stack>` read the
variable (or prompt).

## First-deploy inputs

The stacks hold placeholders. Replace them before any apply against a real account.

| Input | Where |
|-------|-------|
| Workload account IDs | `settings.environment.account_id` in `stacks/orgs/fnx/{dev,staging,prod}/_defaults.yaml`; `settings.environment.aws_account_id` in `staging-01.yaml` and `production.yaml` (dev reads it from `AWS_ACCOUNT_ID`); the CI role ARNs in `access_roles` of `stacks/orgs/fnx/core/us-east-1/root.yaml` |
| Management account ID | `settings.environment.management_account_id` in `stacks/orgs/fnx/_defaults.yaml` |
| AWS Organization ID | `trusted_principal_org_id` in `stacks/catalog/iam/defaults.yaml` |
| Cross-account role callers | `trusted_principal_arns` in `stacks/catalog/iam/defaults.yaml`: the management-account role ARNs (path included) allowed to assume each workload account's `-CrossAccountRole`. The placeholder `<tenant>-cross-account-operator` matches nobody until it exists |
| Cognito feature plan | `user_pool_tier: PLUS` with `advanced_security_mode: ENFORCED` in `stacks/catalog/cognito/defaults.yaml`: PLUS is billed from the first monthly active user. `OFF` + `ESSENTIALS` per instance is the cheaper choice |
| Domains | `settings.environment.domain_name` in each stack's `components/globals.yaml`; every zone, record, certificate and API domain derives from it |
| Alert recipients | `alarm_email_subscriptions` on monitoring instances and the lists in `components/globals.yaml`; each address must confirm its SNS subscription |
| Prod RDS alarm target | `sns_topic_arn` on prod's `rds/main`: unset, so its CloudWatch alarms have no action |
| Lambda packages | the application repo that builds them, as `lambda_uploader_trusted_github_repos` on each stack's `iam/ci` (`components/security.yaml`), then a first upload per function: see [Lambda packages](#lambda-packages). Until then every `lambda/*` instance is `metadata.enabled: false` |
| GitHub | default-branch protection, applied: PR required, linear history, no force-push, required check `CI gate` (the `terraform-ci.yml` job that reports on every PR and fails if any CI job failed). No tag ruleset guards `refs/tags/deployed/**`: on a personal repo GitHub Actions cannot be a ruleset bypass actor, and a ruleset without that bypass blocks `terraform-cd.yml`'s own tag moves. Add it once the repo moves to an organization |
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
| `AWS_REGION` | optional override (default `us-east-1`) |

CD derives each stack's apply role from its `iam/ci` (`workflows/scripts/common/ci-apply-role-arn.py`).
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
`addons`, `services`, `monitoring`.

The selection of each layer is in `workflows/deploy-full-stack.yaml`. An instance that reads
another's state must be in a later layer; `check-deploy-layers.py` (validate-all) enforces that
and that every enabled instance is in exactly one layer.

**Before `certificates`: delegate the stack's domain.** ACM validates in `network/main`'s `main`
zone, so its domain must resolve, or validation times out after 45 minutes. Prod's
`fnx.example.com` is delegated at the registrar to prod's `zone_name_servers.main`
(`atmos terraform output network/main -s fnx-prod-production`). Dev's and staging's parent is
that Terraform-managed zone: add an NS record for `dev.`/`staging.fnx.example.com` to prod's
`network/main` `records` (`stacks/orgs/fnx/prod/us-east-1/production/components/networking.yaml`)
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

An operator applies them through the VPC with their own role, a named cluster admin (the creator
gets no implicit admin, and the CI apply role trusts only GitHub OIDC on master):

1. Once per stack, the owner names the role (full ARN, path kept, e.g.
   `arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/<sso-region>/AWSReservedSSO_AdministratorAccess_<hash>`
   (`<sso-region>` is the IAM Identity Center home region, not the stack's),
   from `aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`) in two places:
   `map_additional_iam_roles` (`groups: ["system:masters"]`) in the stack's `components/globals.yaml`,
   which gives every `eks` instance an `AmazonEKSClusterAdminPolicy` access entry; and
   `backend/main`'s `access_roles.write` (dev/staging) or `.prod_write` (prod) in
   `stacks/orgs/fnx/core/us-east-1/root.yaml`, so it can write the stack's state. Apply `backend/main`
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

Each `stacks/catalog/templates/<t>.yaml` has a never-deployed stack `fnx-fixtures-<name>`
(`stacks/orgs/fnx/fixtures/us-east-1/<name>.yaml`; short names, since templates put the environment
into length-limited AWS names), so lint, validate-all and plan-sweep check templates no real stack
imports. A fixture listed in `KNOWN_BROKEN_FIXTURES` (`workflows/scripts/common/fixtures.py`) has
the listed checks' failures printed as `KNOWN-BROKEN` without failing; a template port PR removes
its entry, which makes the fixture strict. plan-sweep does not sweep a fixture whose entry is `ALL`
(check-dependencies still reports it); narrowing or removing the entry puts it back in the sweep.

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
  `atmos workflow providers-lock -f providers` (`UPGRADE=false` keeps the locked versions), then
  commit the locks. A new major is a deliberate constraint change; Dependabot ignores majors.
- **Atmos image.** Every workflow runs `ghcr.io/cloudposse/atmos:<tag>@sha256:<digest>`, one
  literal repeated (there is no `vars` override: a digest needs a fixed tag). Dependabot bumps the
  copy in `.github/atmos-image/Dockerfile`; run `bash scripts/sync-atmos-image.sh` on its branch
  (the actionlint job fails until you do). By hand: put the new tag and the digest of its manifest
  index (`docker buildx imagetools inspect ghcr.io/cloudposse/atmos:<tag>`, or the ghcr registry
  API) in that Dockerfile and run the script; it also sets `atmos-version` in `emulator.yml`.
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
STACK=<stack> atmos workflow dr-failover -f disaster-recovery        # interactive, never from CI
STACK=<stack> atmos workflow dr-failback -f disaster-recovery
```

The stacks run in `us-east-1`; the DR region is `us-east-2` (`dr-failover`'s default target,
`DR_REGION` in `dr-status`).

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
| A string input rejects a `!terraform.state` value as an object | The output is a JSON string (a `*_policy`); end the read with `\| tojson` |
| ACM validation times out after 45 minutes | The stack's domain is not delegated; see [Deploying a stack](#deploying-a-stack) |
