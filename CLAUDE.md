# CLAUDE.md - tf-atmos

Terraform/Atmos IaC for the `fnx` tenant: 42 root modules in `components/terraform/` (plus
`_library/`), stacks `fnx-dev-testenv-01`, `fnx-staging-staging-01`, `fnx-prod-production`,
`fnx-core-root` (state backend, not run by CI) and the emulator stacks `fnx-local-sandbox`,
`fnx-local-localemu`. Atmos >= 1.229.0 installs Terraform 1.16.3. No Python CLI: use `atmos`.
Layout and conventions: [README.md](./README.md). Operating: [docs/OPERATIONS.md](./docs/OPERATIONS.md).

## Essential commands

```bash
atmos list stacks / components / workflows
atmos describe component <component> -s <stack> --process-functions=false

atmos validate stacks                                  # offline
atmos workflow lint -f lint                            # fmt, yamllint, state keys, tflint, trivy
atmos workflow validate-all -f validate-enhanced       # schema, stacks, dependency/layer/domain checks, fmt, terraform validate
bash scripts/plan-sweep.sh [<stack>...]                # plans with resolved vars, no AWS account

atmos terraform plan <component> -s <stack>
atmos terraform deploy <component> -s <stack>          # plan + apply one instance
atmos workflow deploy -f deploy-full-stack -s <stack>  # layered, confirmed per layer
```

## Gotchas

- `atmos describe stacks`/`describe component` need `--process-functions=false`; otherwise Atmos
  evaluates `!terraform.state` and needs live AWS state.
- validate-all runs `terraform init`/`validate` serially over every root module: set
  `TF_PLUGIN_CACHE_DIR` first.
- `terraform validate` skips `variable` validation blocks. Prove a validation change with
  plan-sweep or an emulator lane, including a deliberately bad value.
- Cross-component values: `!terraform.state <instance> .<output>`, never `${...}`. Each target
  must be in the reader's `dependencies.components` (`check-dependencies.py`) and in an earlier
  layer of `workflows/deploy-full-stack.yaml` (`check-deploy-layers.py`).
- `metadata.component` decides the module: `network/main` is a `dns` instance.
- State keys must stay in their stage's prefix (`check-state-keys.py`); state roles are split by
  stage.
- 36 of the 42 root modules validate a non-empty `tags.Environment` (all but `backend`, `dns`,
  `iam`, `idp-platform`, `kms`, `secretsmanager`); many use it in resource names.
- `idp-platform` calls `../eks`, `../rds`, `../acm` as modules: grep for `source = "../<component>"`
  before changing their variables.
- CI runs in the `ghcr.io/cloudposse/atmos` Linux container; shell that works on macOS may not.

## Conventions

- Follow Cloud Posse: copy upstream variable names, types and defaults; typed objects, never
  `map(any)`; comment every deviation with the upstream source.
- Component files: `main.tf` (or split), `variables.tf`, `outputs.tf`, `versions.tf`
  (`>= 1.16.0, < 2.0.0`), `provider.tf` (`default_tags` from `var.tags`), `README.md`.
  New components: `atmos scaffold generate component . --force`.
- READMEs are purpose + wiring + gotchas only, no input/output tables; `variables.tf` and
  `outputs.tf` are the reference.
- Singular component names without hyphens; snake_case; booleans prefixed `is_`/`has_`/`enable_`;
  validation blocks on variables; `sensitive = true` on sensitive outputs.
- Tags come once from `default_tags` (`stacks/orgs/fnx/_defaults.yaml`), not per resource.
- Disable an instance with `metadata.enabled: false`, never by deleting it.
- Encrypt at rest and in transit; least-privilege IAM; secrets in Secrets Manager; ingress never
  `0.0.0.0/0` or `::/0` (egress is unrestricted).

## Before marking work complete

- [ ] `atmos workflow lint -f lint` and `atmos workflow validate-all -f validate-enhanced` pass
- [ ] Naming, tag and validation conventions followed
- [ ] Docs that name a changed command, workflow, role or path are updated
