# CLAUDE.md - tf-atmos

Terraform/Atmos IaC for the `fnx` tenant. Layout, stacks, quickstart and conventions:
[README.md](./README.md) (read it first). Bootstrap, deploy, state and DR:
[docs/OPERATIONS.md](./docs/OPERATIONS.md). There is no Python CLI: use `atmos`.

## Agent commands

```bash
atmos describe component <component> -s <stack> --process-functions=false   # resolved config, offline
atmos workflow lint -f lint && atmos workflow validate-all -f validate-enhanced  # the gate before committing
bash scripts/plan-sweep.sh [<stack>...]    # proves variable validations without AWS
atmos workflow security-scan -f lint       # local Trivy + Checkov gate (new HIGH/CRITICAL only)
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
- A `!terraform.state`/`!terraform.output` read of a JSON-string output (e.g. a `*_policy`) into a `type = string`
  input needs `| tojson` (`'.producer_policy | tojson'`); otherwise Atmos decodes it into an object.
- A stack template that repeats a component's `<Environment>-<x>` name writes `{{ .settings.prefix }}-<x>`
  (the region code, plus `-<name>` on a lane), never `settings.context.environment`; the full id is
  `{{ .atmos_stack }}`. `check-lane-names.py` fails a lane that shares a name with its stage stack.
- `metadata.component` decides the module: `network/main` is a `dns` instance.
- Each stack's state is an exact `object_key_patterns` pair on its stage's backend roles
  (`stacks/orgs/fnx/core/us-east-1.yaml`): a new stack needs its pair (`check-state-keys.py`).
- Stage `fixtures` (`fnx-ue1-fixtures-<name>`) puts each catalog template under the checks and is
  never deployed; `KNOWN_BROKEN_FIXTURES` (`workflows/scripts/common/fixtures.py`) relaxes a
  template until its port PR removes the entry.
- 43 of the 48 root modules validate a non-empty `tags.Environment` (all but `backend`, `dns`,
  `iam`, `kms`, `secretsmanager`); many use it in resource names.
- checkov's HCL parser rejects a unary `!x`/`-x` that ends a line before a line starting with a binary
  operator (`&&`, `||`, ...) and skips the file: write `x == false` or `(!x)`. The lint step
  `hcl-unary-newline` (`scripts/check-hcl-unary-newline.py`) catches it.
- CI runs in the `ghcr.io/cloudposse/atmos` Linux container; shell that works on macOS may not.
- No scanner baselines: fix a checkov/trivy finding or suppress it inline with a reason
  (`#checkov:skip=<ID>:<reason>` inside the block, `#trivy:ignore:<ID> <reason>` on the line above);
  a risk the owner has not accepted starts with `TODO(owner):` and is tracked in
  [#303](https://github.com/hemzaz/tf-atmos/issues/303) (skips don't show as code-scanning alerts;
  add new ones there).
- Every root module commits `.terraform.lock.hcl` and every init uses `-lockfile=readonly`: after
  a `required_providers` change run `atmos workflow providers-lock -f providers` and commit the locks.

## Before marking work complete

- [ ] `atmos workflow lint -f lint` and `atmos workflow validate-all -f validate-enhanced` pass
  (security-scan runs in CI; run it locally when touching scanner config or adding resources)
- [ ] README conventions followed (Cloud Posse shape, naming, tags, `metadata.enabled: false`)
- [ ] Component READMEs stay purpose + wiring + gotchas, no input/output tables
- [ ] Docs that name a changed command, workflow, role or path are updated
