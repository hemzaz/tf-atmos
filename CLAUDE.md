# CLAUDE.md - Terraform/Atmos Infrastructure Project

This is a **Terraform/Atmos infrastructure-as-code project** with:
- **22 Terraform root modules** in `components/terraform/` (plus `_library/` and `_catalog/`)
- **3 stacks**: `fnx-dev-testenv-01`, `fnx-staging-staging-01`, `fnx-prod-production` (eu-west-2)
- **Atmos workflows** in `workflows/` (`atmos list workflows`) and **Atmos Native CI** in `.github/workflows/`
- Atmos >= 1.229.0 (enforced in `atmos.yaml`); Terraform 1.16.3 is installed by the Atmos toolchain
- S3 state backend `fnx-terraform-state` with native lockfiles (`use_lockfile`), no DynamoDB

There is no Python CLI; use `atmos` commands and workflows.

## Essential commands

```bash
atmos list stacks / components / workflows
atmos describe component <component> -s <stack>       # resolved config for one instance

atmos validate stacks                                  # offline, no AWS credentials
atmos workflow validate-all -f validate-enhanced        # schema, stacks, yamllint, fmt, terraform validate
atmos workflow lint -f lint                             # fmt, yamllint, tflint, trivy — run before committing

atmos terraform plan <component> -s <stack>
atmos terraform deploy <component> -s <stack>           # plan + apply one instance
atmos workflow deploy -f deploy-full-stack -s <stack>    # layered, confirmed per layer
```

## Gotchas

- `atmos describe stacks`/`describe component` calls must pass `--process-functions=false`
  (`--format json`) — without it Atmos evaluates `!terraform.state` etc. and needs live AWS state.
- The `validate-all` workflow (`validate-root-modules` step) runs `terraform init`/`validate`
  **serially** across every root module in a `for` loop. Set `TF_PLUGIN_CACHE_DIR` first or each
  module redownloads providers.
- Tags must include `Tenant`, `Account`, `Environment`, `ManagedBy = "Terraform"` (set once via
  `default_tags` in each `provider.tf`, sourced from `stacks/orgs/fnx/_defaults.yaml`) — don't
  repeat them per resource.
- Cross-component values use YAML functions (`!terraform.state <component> .<output>`), never
  `${...}` interpolation.
- Component naming is singular, no hyphens (`securitygroup`, not `security-groups`). Boolean
  variables prefix with `is_`, `has_`, or `enable_`.
- Disable an instance with `metadata.enabled: false`, not by deleting it.
- `var.tags` must contain a non-empty `Environment` (validated) in vpc, monitoring, external-secrets,
  rds, lambda and securitygroup: it is used in resource names. `atmos terraform lint` runs tflint
  without stack vars, so these variables stay required (no `{}` default) to keep tflint from crashing.
- `idp-platform` calls `../eks`, `../rds` and `../acm` as modules. Before changing their variables,
  grep for `source = "../<component>"`; `validate-all` catches the breakage, per-component checks don't.

## Conventions

- Per-component files: `main.tf` (or split into `iam.tf`, `locals.tf`, ...), `variables.tf`,
  `outputs.tf`, `versions.tf` (`>= 1.16.0, < 2.0.0` + `required_providers`), `provider.tf`,
  `README.md` — every component needs one.
- snake_case for resources/variables/outputs; `sensitive = true` on sensitive outputs; validation
  blocks on variable definitions.
- Encrypt at rest and in transit; least-privilege IAM; secrets in Secrets Manager, never committed;
  specific CIDRs, never `0.0.0.0/0`.

## Before marking work complete

- [ ] `atmos workflow lint -f lint` and `atmos workflow validate-all -f validate-enhanced` pass
- [ ] Tags, naming and validation conventions above followed
- [ ] Component `README.md` updated if its interface changed
