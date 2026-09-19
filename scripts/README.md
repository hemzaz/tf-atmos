# Helper Scripts

Bash helpers around the `atmos` CLI. Day-to-day operations go through Atmos
workflows (`atmos list workflows`) and the root `Makefile`; these scripts cover
scaffolding, local setup and certificate operations.

Stacks are named by `name_template` as `<tenant>-<stage>-<environment>`
(e.g. `fnx-dev-testenv-01`); naming context lives in `settings.context`.

## Scripts

| Script | Purpose |
|--------|---------|
| `list_stacks.sh [--plain]` | List stacks with tenant/stage/environment/account/region |
| `new-environment.sh` | Scaffold a new stack under `stacks/orgs/<tenant>/<stage>/<region>/` |
| `manifest-generator.sh` | Dump stack/component manifests; scaffold components and stacks |
| `quickstart.sh` | Check prerequisites, create a stack, bootstrap the backend, deploy |
| `install-dependencies.sh` | Install CLI tools at the versions pinned in `.atmos.env` |
| `update-versions.sh` | Check or bump the versions in `.atmos.env` |
| `dev-setup.sh` | Local dev environment setup |
| `onboard-developer.sh` | Onboarding checklist for a new developer |
| `validate-terraform.sh` | Ad hoc Terraform validation helper |
| `check-shell-compat.sh` | Check scripts for bash/POSIX portability issues |
| `collect-dx-feedback.sh` | Collect developer-experience feedback |
| `utils.sh` | Shared shell functions sourced by the scripts above |

`dr/` holds disaster-recovery backup procedures (Velero, S3).

## Certificates

`certificates/` has the TLS certificate and SSH key operations against AWS Secrets Manager, ACM and
Kubernetes (`rotate-cert.sh`, `rotate-ssh-key.sh`, `generate-ssh-key.sh`, `export-cert.sh`,
`export-ssh-key.sh`, `monitor-certificates.sh`, plus shared `certificate-utils.sh`). Run them
directly or through the workflow:

```bash
atmos workflow rotate -f rotate-certificate
./scripts/certificates/rotate-cert.sh -s <secret_name> -n <namespace> [-a <acm_cert_arn>]
```

Each script prints its options with `-h`.

## Usage

```bash
./scripts/list_stacks.sh
./scripts/new-environment.sh --tenant fnx --stage dev --environment testenv-02 --region eu-west-2
atmos workflow plan -f plan-environment -s fnx-dev-testenv-01
```

Scripts that only applied to the pre-migration layout (DynamoDB locking,
`vars.tenant`-style catalogs) exit immediately with a pointer to their replacement.
