# CLAUDE.md - tf-atmos

Terraform/Atmos IaC for the `fnx` tenant. Layout, stacks, quickstart and conventions:
[README.md](./README.md) (read it first). Bootstrap, deploy, state and DR:
[docs/OPERATIONS.md](./docs/OPERATIONS.md). There is no Python CLI: use `atmos`.

## Agent commands

```bash
atmos describe component <component> -s <stack> --process-functions=false   # resolved config, offline
atmos workflow lint -f lint && atmos workflow validate-all -f validate-enhanced  # the gate before committing
bash scripts/plan-sweep.sh [<stack>...]    # proves variable validations without AWS
```

Nothing has been applied to AWS yet, so refactors need no state migration.

## Gotchas

- `atmos describe stacks`/`describe component` need `--process-functions=false`; otherwise Atmos
  evaluates `!terraform.state` and needs live AWS state.
- validate-all runs `terraform init`/`validate` serially over every root module: set
  `TF_PLUGIN_CACHE_DIR` first.
- `terraform validate` skips `variable` validation blocks. Prove a validation change with
  plan-sweep or an emulator lane, including a deliberately bad value.
- A new `!terraform.state` read needs the target in the reader's `dependencies.components`
  (`check-dependencies.py`) and in an earlier layer of `workflows/deploy-full-stack.yaml`
  (`check-deploy-layers.py`).
- `metadata.component` decides the module: `network/main` is a `dns` instance.
- State keys must stay in their stage's prefix (`check-state-keys.py`).
- 36 of the 42 root modules validate a non-empty `tags.Environment` (all but `backend`, `dns`,
  `iam`, `idp-platform`, `kms`, `secretsmanager`); many use it in resource names.
- `idp-platform` calls `../eks`, `../rds`, `../acm` as modules: grep for `source = "../<component>"`
  before changing their variables.
- CI runs in the `ghcr.io/cloudposse/atmos` Linux container; shell that works on macOS may not.

## Before marking work complete

- [ ] `atmos workflow lint -f lint` and `atmos workflow validate-all -f validate-enhanced` pass
- [ ] README conventions followed (Cloud Posse shape, naming, tags, `metadata.enabled: false`)
- [ ] Component READMEs stay purpose + wiring + gotchas, no input/output tables
- [ ] Docs that name a changed command, workflow, role or path are updated
