# Helper Scripts

Bash helpers around the `atmos` CLI. Day-to-day operations go through Atmos
workflows (`atmos list workflows`) and the root `Makefile`; these scripts cover
scaffolding, local setup and certificate operations.

Stacks are named by `name_template` as `<tenant>-<stage>-<environment>`
(e.g. `fnx-dev-testenv-01`); naming context lives in `settings.context`.

## Directory Structure

- **certificates/**: TLS certificate and SSH key operations (see its README)
- **dr/**: Disaster-recovery backup procedures (Velero, S3)
- **workflows/**: Legacy workflow templates for the removed `gaia` CLI (not loaded by Atmos)

## Common Scripts

| Script | Purpose |
|--------|---------|
| `list_stacks.sh [--plain]` | List stacks with tenant/stage/environment/account/region |
| `new-environment.sh` | Scaffold a new stack under `stacks/orgs/<tenant>/<stage>/<region>/` |
| `manifest-generator.sh` | Dump stack/component manifests; scaffold components and stacks |
| `quickstart.sh` | Check prerequisites, create a stack, bootstrap the backend, deploy |
| `install-dependencies.sh` | Install CLI tools at the versions pinned in `.atmos.env` |
| `update-versions.sh` | Check or bump the versions in `.atmos.env` |

## Usage

```bash
./scripts/list_stacks.sh
./scripts/new-environment.sh --tenant fnx --stage dev --environment testenv-02 --region eu-west-2
atmos workflow plan -f plan-environment -s fnx-dev-testenv-01
```

Scripts that only applied to the pre-migration layout (DynamoDB locking,
`vars.tenant`-style catalogs, the `gaia` CLI) exit immediately with a pointer
to their replacement.
