# Terraform Atmos Infrastructure

AWS infrastructure for the `fnx` tenant, defined as Terraform root modules and composed into
stacks with [Atmos](https://atmos.tools/). Deployments run through Atmos workflows locally and
Atmos Native CI in GitHub Actions.

> Before the first `apply`, replace the placeholder account IDs, organization ID, domains and
> alert recipients. The list is in
> [Manual prerequisites before first apply](./docs/DEPLOYMENT.md#manual-prerequisites-before-first-apply).

## This repository is opinionated: it follows Cloudposse

Atmos is a Cloudposse utility, engineered around a particular way of working. Cloudposse know
their product best, and they define how it should consume Terraform, Helm and other modules.
So this repository follows Cloudposse all the way rather than inventing its own conventions.

In practice that means:

- **Component variables copy the upstream shape.** When a Cloudposse module or reference
  component already models something, its variable names, types and defaults are copied
  verbatim — defensive extras included. `clusters[*].node_groups.block_device_map` in
  `components/terraform/eks` is copied from
  [`cloudposse-terraform-components/aws-eks-cluster`](https://github.com/cloudposse-terraform-components/aws-eks-cluster),
  down to the camel-case decoy attributes that turn a silently-dropped typo into a loud error.
- **Typed objects, never `map(any)`.** `map(any)` forces every element to converge on one type,
  so two entries differing by a single optional key cannot coexist, and any key the component
  does not read is discarded without a warning.
- **Upstream removals are respected.** Cloudposse deleted `disk_size`, `disk_type` and
  `disk_encryption_enabled` from their node-group module because those are launch-template-only
  settings that AWS rejects alongside a node group's own `disk_size`. This repository does not
  reintroduce them.
- **Deviations are documented.** Where this repository departs from upstream it says so in a
  comment beside the code, with the reason.

When a design question has no obvious answer, the tiebreaker is: do what Cloudposse does, and
keep a comment naming the upstream source so the code can be re-synced later. Note that the old
`cloudposse/terraform-aws-components` monorepo is archived — current reference components live
under [`cloudposse-terraform-components`](https://github.com/cloudposse-terraform-components).

## Versions

| Tool | Version | Where it's pinned |
|------|---------|--------------------|
| Atmos | >= 1.229.0 | `atmos.yaml` (`version.constraint`, fatal) |
| Terraform | 1.16.3 | `stacks/orgs/fnx/_defaults.yaml` (`terraform.dependencies.tools`); Atmos installs it |
| AWS provider | `~> 6.65` in root modules, `>= 6.0, < 7.0` in shared modules | each `versions.tf` |
| Kubernetes / Helm providers | 3.x | `versions.tf` of the EKS-related components |

Lint, scan and AWS CLI tools (tflint, yamllint, trivy, checkov, aws-cli, jq) are pinned in the
workflows that use them and installed by the Atmos toolchain — no separate install step.

## Quick start

Prerequisites: Atmos >= 1.229.0 and AWS credentials for the target account. You do not need to
install Terraform — Atmos downloads the pinned version the first time a component runs.

```bash
atmos version                     # must be >= 1.229.0
atmos list stacks                 # the three real stacks plus fnx-local-sandbox and fnx-local-localemu
atmos list components             # component instances and how many stacks use each
atmos list workflows              # every workflow with its file and description

# Offline checks (no AWS credentials needed)
atmos validate stacks
atmos workflow validate-all -f validate-enhanced

# Run it for real with no AWS account (Docker only) - see Sandbox below
atmos workflow sandbox -f sandbox

# First deployment of a stack (creates the state bucket, then IAM and VPCs)
atmos workflow full -f bootstrap -s fnx-dev-testenv-01

# Everything else, layer by layer (each layer is planned, confirmed, then applied)
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01
```

The full procedure is in the [Deployment Guide](./docs/DEPLOYMENT.md).

## Layout

```
atmos.yaml                  Atmos CLI config (version constraint, paths, name_template, Native CI)
components/terraform/       Terraform root modules (+ _library/ shared modules)
modules/terraform/          Provider-less shared modules
stacks/
  orgs/fnx/                 Org, account and region defaults, and the three stacks
  catalog/                  Abstract component defaults, disabled variants, stack templates
  mixins/                   Tenant, stage and region mixins
workflows/                  Atmos workflows (+ scripts/ they call)
.github/workflows/          CI, CD, drift detection, security scan, DR checks
docs/                       Deployment and operations guides
```

## Stacks

Stack names come from `name_template` in `atmos.yaml`:
`{{ .settings.context.tenant }}-{{ .settings.context.stage }}-{{ .settings.context.environment }}`.

| Stack | Manifest | Region |
|-------|----------|--------|
| `fnx-dev-testenv-01` | `stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` | eu-west-2 |
| `fnx-staging-staging-01` | `stacks/orgs/fnx/staging/eu-west-2/staging-01.yaml` | eu-west-2 |
| `fnx-prod-production` | `stacks/orgs/fnx/prod/eu-west-2/production.yaml` | eu-west-2 |
| `fnx-local-sandbox` | `stacks/orgs/fnx/local/eu-west-2/sandbox.yaml` | eu-west-2 (emulated) |
| `fnx-local-localemu` | `stacks/orgs/fnx/local/eu-west-2/localemu.yaml` | eu-west-2 (emulated) |

The three real stacks each import five domain files from their `components/` directory
(`globals`, `networking`, `security`, `compute`, `services`). See
[stacks/README.md](./stacks/README.md). The two `fnx-local-*` stacks are local emulator lanes —
`fnx-local-sandbox` runs against Floci, `fnx-local-localemu` against LocalEmu for the components
Floci cannot provision. See [Sandbox](#sandbox).

## Sandbox

The repository runs end to end with no AWS account, no credentials and no cost:

```bash
atmos workflow sandbox -f sandbox     # up, apply, destroy, down
```

That starts a [Floci](https://github.com/floci-dev/floci) container (MIT-licensed, a drop-in for
LocalStack CE, which was end-of-lifed in March 2026), applies `kms`, `vpc`, `dns`,
`secretsmanager`, `ecs`, `lambda`, `cognito` and `securitygroup` against it for real, then
destroys them in reverse and stops the container. Docker is the only prerequisite. Individual
steps:

```bash
atmos emulator up aws -s fnx-local-sandbox
atmos terraform apply vpc/main -s fnx-local-sandbox --identity local-aws
atmos emulator down aws -s fnx-local-sandbox
```

Together with the LocalEmu lane below, this is how the repo **executes** Terraform rather than
just analyzing it, and it has caught bugs every static check missed — a NAT gateway created
despite `nat_gateway_enabled = false`, a `coalesce()` that would have failed every `iam` plan, and
a missing `database_subnet_ids` output that would have broken all three `rds` instances at plan
time.

Two things to know:

- The `local-aws` identity is deliberately **not** `default: true`, so no real environment can be
  pointed at the emulator by accident. Pass `--identity local-aws` explicitly.
- The emulator does not implement everything. `CreateNetworkAcl` is missing, and there is
  no VPC default security group to adopt, which is why the sandbox stack sets
  `manage_network_acls: false` and `manage_default_security_group: false`. `CreateDBSubnetGroup` is missing too, so `rds` cannot run against
  Floci — it is exercised against LocalEmu instead, in the `fnx-local-localemu` lane, which is
  what caught the overlapping backup and maintenance windows that would have failed
  `CreateDBInstance` in staging and prod. Components with an instance in neither lane are covered
  by validation and scanners only — their READMEs say so.

## Components

`components/terraform/` holds 42 root modules, plus `_library/` (shared modules): `acm`, `alb`,
`alb-controller-ingress-group`, `apigateway`, `athena`, `awsconfig`, `backend`, `backup`,
`cloudtrail`, `cognito`, `cost-optimization`, `dns`, `dynamodb`, `ec2`, `ecs`, `eks`,
`eks-addons`, `eks-backend-services`, `elasticache`, `eventbridge`, `external-secrets`, `glue`,
`guardduty`, `iam`, `idp-platform`, `kinesis`, `kms`, `lambda`, `monitoring`, `network`, `rds`,
`s3`, `secretsmanager`, `security-monitoring`, `securitygroup`, `securityhub`, `ses`, `sns`,
`sqs`, `stepfunctions`, `vpc`, `waf`.

`idp-platform` is unsupported (no stack deploys it; `plan` fails unless
`acknowledge_unsupported = true`). There are no `metadata.enabled: false` instances left in
`stacks/orgs/`, but not every component has an instance: `alb`, `alb-controller-ingress-group`,
`athena`, `dynamodb`, `eventbridge`, `glue`, `kinesis`, `s3`, `ses`, `sns`, `sqs`, `stepfunctions`
and `waf` are used only by the opt-in [stack templates](./stacks/README.md#stack-templates),
`securitygroup` is deployed only in `fnx-local-sandbox`, and every other component except
`idp-platform` has an instance in the three real stacks.

An instance name does not have to match its component: `metadata.component` decides which module
runs. `network/main` and `network/services` are `dns` instances, while `network/vpc-peering` is
the `network` module. Read `metadata.component` before assuming.

Every root module has `versions.tf`, `provider.tf` (AWS provider with `default_tags` from
`var.tags`) and a `README.md`. Tags come from `stacks/orgs/fnx/_defaults.yaml`: `Tenant`,
`Account`, `Environment`, `ManagedBy = "Terraform"`.

**State backend**: S3 bucket `fnx-terraform-state`, accessed through `fnx-terraform-backend-role`
in the management account. Locking uses Terraform's native S3 lockfiles (`use_lockfile: true`); no
DynamoDB lock table.

## Adding a component

Components are scaffolded, not hand-written, so a new one satisfies the house rules (required
`tags` with a non-empty `Environment`, `enabled` gating, `versions.tf`, `provider.tf` with
`default_tags`, a README) before it is first linted:

```bash
atmos scaffold generate component . --force          # prompts for name, description, category
atmos scaffold generate catalog-entry . --force      # catalog defaults for an existing component
```

The target is the **repository root**, not the component directory: the template's `files[].target`
paths place each file, which is what lets one run emit both the component and its catalog entry.
Templates live in `scaffolds/` and are registered in `atmos.yaml` under `scaffold.templates`.
`--update` re-runs a template over existing files with a 3-way merge.

## Checks

```bash
atmos workflow tflint-init -f lint   # once: installs TFLint and the rulesets in .tflint.hcl
atmos workflow lint -f lint          # terraform fmt, yamllint, TFLint (instances + directories), Trivy
atmos workflow validate-all -f validate-enhanced   # schema, stacks, dependencies, yamllint, fmt, terraform validate
atmos workflow validate -f validate -s <stack>     # same, scoped to one stack
atmos workflow sandbox -f sandbox                  # applies real resources against Floci (local only, not yet in CI)
atmos workflow localemu -f localemu                # applies real resources against LocalEmu (vpc, lambda, rds, monitoring, iam); also runs in CI's emulator.yml
```

Two gates are worth understanding, because both were added after they let real bugs through:

- **TFLint runs twice.** The instance pass resolves stack variables and catches what only appears
  with real inputs; the directory pass walks `components/terraform/*/` so a component with no
  stack instance cannot go unlinted. Ten of the components were unlinted before the second pass
  existed, while the gate reported "passed".
- **`check-dependencies.py` maps instances back to directories.** A deployable instance naming a
  component that does not exist used to pass every gate, because neither `atmos validate stacks`
  nor validate-all checks that the directory is there.

Note that `terraform validate` does **not** evaluate `variable` validation blocks, so validate-all
never exercises them. Changes to a validation block need a plan against real values to prove it
behaves — including a deliberately-bad case, to prove the check is reached at all.

## CI/CD

GitHub Actions run Atmos Native CI inside the `ghcr.io/cloudposse/atmos` container and
authenticate to AWS with OIDC, not stored keys.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-ci.yml` | PR, merge queue, push to default branch | Lint + validate-all, plan-sweep, Trivy/Checkov security gate, `terraform test` for components with a `tests/` directory that the change affects (all of them on push and merge queue), plans affected components with the read-only role and comments on the PR (PR/merge-queue only) |
| `emulator.yml` | PR, push to default branch, manual | Runs the LocalEmu lane (`vpc`, `lambda`, `rds`, `monitoring`, `iam`) against a real LocalEmu instance and destroys it — the only CI gate that actually provisions. The Floci [sandbox](#sandbox) lane is not wired into CI yet; it still runs locally |
| `terraform-cd.yml` | push to default branch, manual | Deploys each stack in turn (dev, staging, prod) since its `deployed/<stack>` tag, then moves the tag |
| `drift-detection.yml` | hourly, manual | Plans every stack read-only; drift fails the job |
| `security-scan.yml` | nightly | Report-only Trivy + Checkov scan |
| `disaster-recovery.yml` | manual, default branch | Read-only DR checks |

The AWS jobs above skip until the repository variable `AWS_PLAN_ROLE_ARN` is set — there is no AWS
account wired up yet. The PR security gate fails only on HIGH/CRITICAL findings not already in the
committed baselines (`.trivyignore.yaml`, `.checkov.baseline`).

## Documentation

- [Deployment Guide](./docs/DEPLOYMENT.md): prerequisites, bootstrap, layered deployment, rollback
- [Operations Guide](./docs/OPERATIONS.md): drift, locks, state recovery, DR, security checks
- [Stacks](./stacks/README.md)
- Component READMEs: `components/terraform/<component>/README.md`, `components/terraform/_library/README.md`

## License

MIT, see [LICENSE](./LICENSE).
