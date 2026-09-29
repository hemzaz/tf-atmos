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
components/terraform/    42 root modules (+ _library/ shared modules); each has a README
modules/terraform/       provider-less shared modules
stacks/orgs/fnx/         org defaults (_defaults.yaml: tags, Terraform version, S3 backend) and the stacks
stacks/catalog/          abstract component defaults; templates/ holds opt-in stack templates
stacks/mixins/           tenant, stage and region mixins
workflows/               Atmos workflows (atmos list workflows); scripts/ holds the checks they run
scripts/                 helpers: plan-sweep.sh, new-environment.sh, certificates/, dr/
scaffolds/               templates for `atmos scaffold generate`
templates/, examples/    copy-in component template, stack/config samples, the OIDC hub/spoke example
integrations/            Atlantis and Jenkins alternatives to GitHub Actions (not used by CI)
.github/workflows/       CI/CD (below)
```

`make help` lists Makefile shortcuts around the same Atmos commands.

## Stacks

Names come from `name_template` in `atmos.yaml`: `<tenant>-<stage>-<environment>`. Only files
under `stacks/orgs/` are stack manifests; each real stack imports its `<env>/components/`
domain files (`globals`, `networking`, `security`, `compute`, `services`).

| Stack | Manifest (`stacks/orgs/fnx/...`) | Purpose |
|-------|----------------------------------|---------|
| `fnx-dev-testenv-01` | `dev/eu-west-2/testenv-01.yaml` | dev |
| `fnx-staging-staging-01` | `staging/eu-west-2/staging-01.yaml` | staging |
| `fnx-prod-production` | `prod/eu-west-2/production.yaml` | production |
| `fnx-core-root` | `core/eu-west-2/root.yaml` | management account: the state backend (`backend/main`); not run by CI |
| `fnx-local-sandbox` | `local/eu-west-2/sandbox.yaml` | Floci emulator lane, no AWS account needed |
| `fnx-local-localemu` | `local/eu-west-2/localemu.yaml` | LocalEmu lane, for what Floci cannot provision (e.g. `rds`) |

An instance name need not match its module: `metadata.component` decides. `network/main` and
`network/services` are `dns` instances; `network/vpc-peering` is the `network` module.

## Prerequisites

- Atmos >= 1.229.0 (fatal constraint in `atmos.yaml`). Atmos installs Terraform 1.16.3
  (`stacks/orgs/fnx/_defaults.yaml`) and the lint/scan tools pinned in each workflow.
- Docker, for the emulator lanes. AWS credentials only for plans/applies against real accounts.
- The stacks still hold placeholder account IDs, domains and alert addresses: see
  [first-deploy inputs](./docs/OPERATIONS.md#first-deploy-inputs).

## Developer quickstart

```bash
atmos list stacks                                   # also: list components, list workflows
atmos describe component vpc/main -s fnx-dev-testenv-01 --process-functions=false
atmos validate stacks                               # offline
atmos workflow tflint-init -f lint                  # once
atmos workflow lint -f lint                         # fmt, yamllint, state-key check, TFLint, Trivy
atmos workflow validate-all -f validate-enhanced    # schema, stacks, dependency/layer/domain checks, fmt, terraform validate
bash scripts/plan-sweep.sh fnx-dev-testenv-01       # plan with resolved variables, no AWS account needed
atmos workflow sandbox -f sandbox                   # apply against Floci, then destroy (Docker only)
atmos workflow localemu -f localemu                 # the same against LocalEmu
atmos terraform plan vpc/main -s fnx-dev-testenv-01 # needs AWS credentials
```

`terraform validate` never evaluates `variable` validation blocks; plan-sweep and the emulator
lanes do. Emulator runs need `--identity local-aws` (sandbox) or `--identity local-emu`
(localemu) when run by hand; neither identity is a default, so no real stack can hit an emulator.

**Add a component:** `atmos scaffold generate component . --force` (run from the repo root; it
also writes the catalog entry). `atmos scaffold generate catalog-entry . --force` adds catalog
defaults for an existing component.

**Add an instance:** add it under `components.terraform` in the stack's domain file, with
`metadata.component` (and `inherits` for the catalog base), then list every instance it reads
in `dependencies.components` and make sure a layer in `workflows/deploy-full-stack.yaml` deploys
it after them. validate-all fails otherwise. A new stack's CI roles must also be added to
`access_roles` in `stacks/orgs/fnx/core/eu-west-2/root.yaml`.

## Conventions

- Cross-component values use YAML functions (`!terraform.state vpc/main .vpc_id`), never
  `${...}`. Every instance read must be in the reader's `dependencies.components`
  (`workflows/scripts/common/check-dependencies.py`).
- Disable an instance with `metadata.enabled: false`, never by deleting it.
- Component names are singular without hyphens (`securitygroup`); snake_case everywhere;
  boolean variables start with `is_`, `has_` or `enable_`.
- Tags (`Tenant`, `Account`, `Environment`, `ManagedBy`) come from `stacks/orgs/fnx/_defaults.yaml`
  and are applied once through `default_tags` in each `provider.tf`, not per resource.
- `settings.list_merge_strategy: replace`: a list in a more specific file replaces the inherited one.
- Inbound access never allows `0.0.0.0/0` or `::/0`; egress is unrestricted.
- Component READMEs cover purpose, wiring and gotchas; `variables.tf` and `outputs.tf` are the
  interface reference.

## CI/CD

Jobs run in the `ghcr.io/cloudposse/atmos` container and use GitHub OIDC. AWS jobs are skipped
until the repository variable `AWS_PLAN_ROLE_ARN` is set.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-ci.yml` | PR, merge queue, push to master | Lint + validate-all, plan-sweep, Trivy/Checkov gate (new HIGH/CRITICAL only, baselines in `.trivyignore.yaml`/`.checkov.baseline`), `terraform test` for components with `tests/`, plan of affected instances with the read-only role and a PR comment. Prod is planned on push to master only |
| `emulator.yml` | PR, push to master, manual | LocalEmu lane: applies and destroys real resources |
| `terraform-cd.yml` | push to master, manual | Per stack (dev, staging, prod): deploys what changed since its `deployed/<stack>` tag with that stack's `iam/ci` apply role, then moves the tag. No manual approval |
| `drift-detection.yml` | hourly, manual | Read-only plan of every stack; drift fails the job |
| `security-scan.yml` | nightly, manual | Report-only Trivy + Checkov |
| `disaster-recovery.yml` | manual | Read-only DR checks (`dr-status`, `recover-state`, `recover-database`) |

## License

MIT, see [LICENSE](./LICENSE).
