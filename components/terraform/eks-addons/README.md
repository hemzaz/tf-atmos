# eks-addons

Deploys AWS EKS managed addons (`aws_eks_addon`), Helm releases, and raw Kubernetes
manifests onto an existing EKS cluster, keyed by entries under `var.clusters`.
Waits for the cluster to reach `ACTIVE` and for addons/Helm releases to settle via
`time_sleep` before proceeding. Can optionally create an IRSA role per addon and
install an Istio gateway chart with a TLS secret sourced from ACM or from
`external-secrets`.

## Deployed instances

Not currently deployed in any of the 3 real stacks (dev, staging, prod) — zero
instances exist today. No stack imports it.

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `clusters` map: each entry needs `cluster_name`, `kubernetes_host`, `cluster_ca_certificate`, `oidc_provider_arn`, `oidc_provider_url` | `istio_enabled`/`domain_name`, `use_external_secrets` | `addon_arns`, `helm_release_statuses`, `service_account_role_arns` (maps) |

## Dependencies & gotchas

- No `dependencies.components` entries exist (no instances anywhere yet); in
  practice this needs a running EKS cluster (e.g. an `eks/*` instance) first.
- Despite `var.clusters` being a map, `provider.tf`'s `kubernetes`/`helm` providers
  authenticate using the separate, deprecated top-level vars (`host`,
  `cluster_ca_certificate`, `cluster_name`) — a single cluster connection, so
  `helm_release`/`kubernetes_manifest` resources for a second map entry would
  still apply against that one connection.
- The Istio TLS secret needs either `acm_certificate_crt`/`acm_certificate_key` or
  `use_external_secrets = true` with `secrets_manager_secret_path` set.

## Usage

A stack must add an instance first. Once added:

```
atmos terraform plan eks-addons/main -s fnx-dev-testenv-01
```
