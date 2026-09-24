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
| `onboard-developer.sh` | Onboarding checklist for a new developer |
| `validate-terraform.sh` | Ad hoc Terraform validation helper |
| `check-shell-compat.sh` | Check scripts for bash/POSIX portability issues |
| `collect-dx-feedback.sh` | Collect developer-experience feedback |
| `plan-sweep.sh` | Bind every stack/component's resolved variables and plan; see [Plan sweep](#plan-sweep) |
| `utils.sh` | Shared shell functions sourced by the scripts above |

`dr/` holds disaster-recovery backup procedures (Velero, S3).

## Plan sweep

`plan-sweep.sh` is the middle rung between `terraform validate` and an emulator
apply: it binds each stack's resolved variables to its component and plans,
catching variable-validation and precondition failures that `terraform
validate` and tflint miss (neither ever binds a value). No AWS account is
needed or used: the script pins its own unissued credentials, so a plan that
reaches the provider stops at the expected, ignored `InvalidClientTokenId`.
Because validations are evaluated before the provider authenticates, they are
always checked; anything a component's plan would only discover after its
first live data source read stays invisible to this sweep.

`plan_sweep_varfile.py` is `plan-sweep.sh`'s varfile builder, called once per
stack/component pair to turn that instance's `atmos describe component` JSON
into a Terraform varfile. `--process-functions=false` leaves Atmos's YAML
functions (`!terraform.state`, `!env`, ...) as literal strings, so this script
substitutes a synthetic value for each one instead of dropping it — built the
same way Atmos itself resolves `!terraform.state`/`!terraform.output`, and
shaped (map, list, object, scalar) from the *referenced* component's actual
output, not guessed from the consuming variable's name, so a shape mismatch
between two components' interfaces is still caught.

`plan_sweep_hcl.py` is `plan_sweep_varfile.py`'s HCL reader: since the CI image
has `python3` and no HCL library, it infers the shape of a referenced
Terraform output by reading the target component's `.tf` source text directly
(skipping strings, interpolations, heredocs and comments correctly), and
reports a shape it cannot determine as unknown rather than guessing.

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
