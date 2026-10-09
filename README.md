# Terraform Atmos Infrastructure

AWS infrastructure for the `fnx` tenant: Terraform root modules composed into stacks with
[Atmos](https://atmos.tools/), deployed by Atmos workflows locally and Atmos Native CI in GitHub
Actions. Operating it (bootstrap, deploy, state, DR) is in [docs/OPERATIONS.md](./docs/OPERATIONS.md).

The repository follows Cloud Posse: when a
[Cloud Posse component](https://github.com/cloudposse-terraform-components) or module already
models something, copy its variable names, types and defaults; use typed objects, never
`map(any)`; document every deviation in a comment beside the code, naming the upstream source.

## Layout

```
atmos.yaml               Atmos config: version constraint, paths, name_template, Native CI, scaffolds
components/terraform/    48 root modules (+ _library/ shared modules); each has a README
stacks/orgs/fnx/         org defaults (_defaults.yaml: tags, Terraform version, S3 backend) and the stacks
stacks/catalog/          abstract component defaults; templates/ holds opt-in stack templates
stacks/mixins/           tenant, stage and region mixins
workflows/               Atmos workflows (atmos list workflows); scripts/ holds the checks they run
scripts/                 helpers: plan-sweep.sh, new-environment.sh, certificates/, dr/
scaffolds/               templates for `atmos scaffold generate`
templates/, examples/    copy-in component template, stack/config samples, the OIDC hub/spoke example
.github/workflows/       CI/CD (below)
```

`make help` lists Makefile shortcuts around the same Atmos commands.

## Stacks

Names come from `name_template` in `atmos.yaml`: `<tenant>-<environment>-<stage>[-<name>]`, Cloud
Posse's null-label id order. `environment` is the region code (`ue1`, set by
`stacks/mixins/region/*`), `stage` the account tier, and the optional `settings.context.name` a lane
within a stage (fixtures, emulator lanes, the `templates/stacks` samples). A lane deploys beside its
stage stack in the same account and region: its names carry the lane (below), and
`check-lane-names.py` (lint) fails two stacks or instances of one account and region that create the same name (and IAM/S3 names across the regions of one account). The
`templates/stacks` samples are such lanes: `scripts/check-stack-samples.sh` copies them in and runs
the stack checks (lint) and plan-sweep (validate-enhanced) over them. Only files under `stacks/orgs/` are stack manifests;
each real stack, `<stage>/<region>.yaml`, imports its `<stage>/<region>/components/` domain files
(`globals`, `networking`, `security`, `compute`, `services`). EU personal data lives only in EU
stacks, tagged `Compliance: "pci-sox-gdpr"` (US prod is `"pci-sox"`): `check-data-residency.py`
(lint) fails a gdpr-tagged stack that names a non-`eu-` region or depends on a non-gdpr stack.

| Stack | Manifest (`stacks/orgs/fnx/...`) | Purpose |
|-------|----------------------------------|---------|
| `fnx-ue1-dev` | `dev/us-east-1.yaml` | dev |
| `fnx-ue1-staging` | `staging/us-east-1.yaml` | staging |
| `fnx-ue1-prod` | `prod/us-east-1.yaml` | production |
| `fnx-ue2-prod` | `prod/us-east-2.yaml` | production DR warm standby, same account; runs a subset of `fnx-ue1-prod` ([Disaster recovery](./docs/OPERATIONS.md#disaster-recovery)) |
| `fnx-ue1-root` | `root/us-east-1.yaml` | management account: the state backend (`backend/main`); not run by CI |
| `fnx-ue1-local-sandbox` | `local/us-east-1/sandbox.yaml` | Floci emulator lane, no AWS account needed |
| `fnx-ue1-local-localemu` | `local/us-east-1/localemu.yaml` | LocalEmu lane, for what Floci cannot provision (e.g. `rds`) |
| `fnx-ue1-fixtures-<name>` | `fixtures/us-east-1/<name>.yaml` | one per `stacks/catalog/templates/` file, checked by CI, never deployed ([details](./docs/OPERATIONS.md#template-fixtures)) |

An instance name need not match its module: `metadata.component` decides. `network/main` and
`network/services` are `dns` instances; `network/vpc-peering` is the `network` module.

## Prerequisites

- Atmos >= 1.229.0 (fatal constraint in `atmos.yaml`). Atmos installs Terraform 1.16.3
  (`stacks/orgs/fnx/_defaults.yaml`) and the lint/scan tools pinned in each workflow.
- Emulator lanes: Docker for the sandbox (Floci); Python 3.13 exactly for LocalEmu (a pip
  package, no Docker). AWS credentials only for plans/applies against real accounts.
- The stacks still hold placeholder account IDs, domains and alert addresses: see
  [first-deploy inputs](./docs/OPERATIONS.md#first-deploy-inputs).

## Developer quickstart

```bash
atmos list stacks                                   # also: list components, list workflows
atmos describe component vpc/main -s fnx-ue1-dev --process-functions=false
atmos validate stacks                               # offline
atmos workflow tflint-init -f lint                  # once
atmos workflow lint -f lint                         # fmt, yamllint, state-key check, TFLint
atmos workflow security-scan -f lint                # Trivy + Checkov gate (any HIGH/CRITICAL not suppressed inline)
atmos workflow validate-all -f validate-enhanced    # schema, stacks, dependency/layer/domain checks, fmt, terraform validate
bash scripts/plan-sweep.sh fnx-ue1-dev              # plan with resolved variables, no AWS account needed
atmos workflow providers-lock -f providers          # after a required_providers change: rewrite the committed locks
atmos workflow sandbox -f sandbox                   # apply against Floci, then destroy (Docker only)
atmos workflow localemu -f localemu                 # the same against LocalEmu (Python 3.13)
atmos terraform plan vpc/main -s fnx-ue1-dev # needs AWS credentials
```

`terraform validate` never evaluates `variable` validation blocks; plan-sweep and the emulator
lanes do. Run the emulator lanes through their workflows: by hand, sandbox commands need
`--identity local-aws`, and LocalEmu commands need `--identity local-emu` plus
`LOCALEMU_ACCESS_KEY_ID`, `LOCALEMU_SECRET_ACCESS_KEY` and `AWS_ENDPOINT_URL`, or the apply reaches
real AWS (`workflows/localemu.yaml`).

**Add a component:** `atmos scaffold generate component . --force` (run from the repo root; it
also writes the catalog entry). `atmos scaffold generate catalog-entry . --force` adds catalog
defaults for an existing component.

**Add an instance:** add it under `components.terraform` in the stack's domain file, with
`metadata.component` (and `inherits` for the catalog base), then list every instance it reads
in `dependencies.components` and make sure a layer in `workflows/deploy-full-stack.yaml` deploys
it after them. validate-all fails otherwise. A new stack also needs its CI roles in the state
backend's trust: see [State backend](./docs/OPERATIONS.md#state-backend).

## Conventions

- Cross-component values use YAML functions (`!terraform.state vpc/main .vpc_id`), never
  `${...}`. Every instance read must be in the reader's `dependencies.components`, and every
  output read and var set must be declared by its module
  (`workflows/scripts/common/check-dependencies.py`).
- Disable an instance with `metadata.enabled: false`, never by deleting it.
- Component names are singular without hyphens (`securitygroup`); snake_case everywhere;
  boolean variables start with `is_`, `has_` or `enable_`.
- Tags (`Tenant`, `Account`, `Environment`, `Stage`, `ManagedBy`) come from
  `stacks/orgs/fnx/_defaults.yaml`, built from `settings.context`, and are applied once through
  `default_tags` in each `provider.tf`, not per resource. `Environment` is `settings.prefix`: the
  region code, plus `-<name>` on a lane (`ue1`, `ue1-serverless`). Components start their names with
  it, and a stack template that repeats such a name writes `{{ .settings.prefix }}-<x>`.
- Names that are global without an account id (S3 buckets without an account suffix, Cognito
  domains) start with the full id, the stack name `<tenant>-<environment>-<stage>[-<name>]`
  (`{{ .atmos_stack }}` in a template), so a lane gets its own. Account-suffixed names
  (`<Environment>-<name>-<account_id>`: the `s3` default, VPC flow logs, CloudTrail, AWS Config,
  ALB logs) are unique per account and region, because each stage has its own account (the
  Cloud Posse model). A value that means the tier (API Gateway `stage_name`, `ENVIRONMENT`
  variables, Kubernetes `environment` labels) reads `settings.context.stage`, never `environment`.
- `settings.list_merge_strategy: replace`: a list in a more specific file replaces the inherited one.
- Each component has `variables.tf` (with validation blocks), `outputs.tf` (`sensitive = true`
  where needed), `versions.tf` (`>= 1.16.0, < 2.0.0`), `provider.tf` and a `README.md` covering
  purpose, wiring and gotchas only; `variables.tf` and `outputs.tf` are the interface reference.
- Encrypt at rest and in transit; least-privilege IAM; secrets in Secrets Manager, never committed.
  Inbound access never allows `0.0.0.0/0` or `::/0`; egress is unrestricted.

## CI/CD

Jobs run in the `ghcr.io/cloudposse/atmos` container and use GitHub OIDC. AWS jobs are skipped
until the repository variable `AWS_PLAN_ROLE_ARN` is set.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-ci.yml` | PR, merge queue, push to master | PR/merge queue: lint + validate-all, actionlint (when `.github/workflows/` changes), plan-sweep, Trivy/Checkov gate (any HIGH/CRITICAL not suppressed inline; no baselines); PR only: plan of affected non-prod instances, each with its stack's read-only `iam/ci` plan role (PR comment), except the in-cluster components (a notice: `in-vpc.yml` plans them on master only). `terraform test` for components with `tests/`: affected ones on PRs, all on merge queue and push. Push to master otherwise runs only the prod plan. A `changes` job skips the jobs whose paths did not change; `CI gate`, the check master's protection requires, runs on every PR and fails if any job, the emulator lane included, failed |
| `emulator.yml` | called by `terraform-ci.yml`, manual | LocalEmu lane: applies and destroys real resources |
| `terraform-cd.yml` | push to master, manual | Per stack (dev, staging, prod): deploys what changed since its `deployed/<stack>` tag with that stack's `iam/ci` apply role, then moves the tag; the [in-cluster components](./docs/OPERATIONS.md#in-cluster-components) deploy on the stack's in-VPC runners (`in-vpc.yml`). No manual approval ([details](./docs/OPERATIONS.md#state-backend)) |
| `drift-detection.yml` | hourly, manual | Read-only plan of every stack, the in-cluster components on the in-VPC runners; drift fails the job |
| `in-vpc.yml` | called by the three above | Starts an ephemeral self-hosted runner in the stack's VPC and runs the in-cluster components there, on the default branch only, with the stack's apply role (a PR gets a notice instead of their plan); the runners themselves refuse fork code |
| `security-scan.yml` | nightly, manual | Report-only Trivy + Checkov |
| `disaster-recovery.yml` | manual | Read-only DR checks (`dr-status`, `recover-state`, `recover-database`) |

## License

MIT, see [LICENSE](./LICENSE).
