# eks-backend-services

Deploys a fixed set of 4 Kubernetes microservices (`api_gateway`, `platform_api`,
`auth_service`, `job_processor`) into a `backend-services` namespace on an existing
EKS cluster: namespace with restricted pod-security labels, a network policy, one
Deployment/Service/ServiceAccount/ConfigMap/HPA/PodDisruptionBudget per service,
`ExternalSecret` resources for database/redis credentials, and optional Prometheus
`ServiceMonitor`s.

The `kubernetes` provider is wired the way this repo's other EKS consumers are
(`eks-addons`, `external-secrets`, `alb-controller-ingress-group`): `host` and
`cluster_ca_certificate` from `eks/main`'s outputs. Unlike `eks-addons`/`external-secrets`,
there is no `aws` CLI `exec` plugin — `data.aws_eks_cluster_auth` provides the
token directly, the same pattern `alb-controller-ingress-group` uses, because the
CI image that runs `terraform validate`/`terraform test` has no `aws` CLI (see the
repo's CI image parity note).

## Deployed instances

`eks-backend-services/main` in all 3 real stacks (fnx-dev-testenv-01,
fnx-staging-staging-01, fnx-prod-production), targeting `eks/main` (not the
`eks/data` cluster). Added to each stack's `compute.yaml`; it plans/applies in
the "services" layer of `workflows/deploy-full-stack.yaml`
(`.metadata.component == "eks-backend-services"`), after compute, platform
(`external-secrets`), data (`rds`/`elasticache`) and addons (`eks-addons`) — so
it can read `rds/main`/`elasticache/main` state on a first deploy.

## Credentials: ExternalSecret, never a Terraform variable

Earlier versions of this component took `database_url`/`database_password`/
`redis_url`/`redis_password` as `sensitive`+`ephemeral` Terraform variables and
wrote them into write-only `kubernetes_secret_v1` resources. That still meant a
plaintext credential had to reach `terraform plan`/`apply` as an input on every
run. This version takes none of that: `kubernetes_manifest.database_external_secret`
(always) and `kubernetes_manifest.redis_external_secret` (when `redis_enabled`)
are `ExternalSecret` resources that reference the `ClusterSecretStore`
`external-secrets/main` already created (`var.cluster_secret_store_name`, its
`default_cluster_secret_store_name` output) and pull straight from Secrets
Manager:

- **database**: `var.database_secret_arn` is `rds/main`'s `password_secret_arn`
  output — the RDS-managed master user secret (`manage_master_user_password`).
  Its JSON has `username`/`password` keys; the ExternalSecret's
  `target.template` builds `database_url` as
  `postgres://{{ .username }}:{{ .password }}@<host:port>/<dbname>`, with
  `<host:port>` (`var.database_endpoint`, `rds/main`'s `instance_endpoint`
  output) and `<dbname>` (`var.database_name`, `instance_name`) as plain,
  non-secret Terraform inputs.
- **redis** (only when `var.redis_enabled`): `var.redis_secret_arn` is
  `elasticache/main`'s new `auth_token_secret_arn` output (see the elasticache
  component's README — its AUTH token is now also stored in Secrets Manager,
  since `elasticache`'s own `auth_token` input never was). `redis_url` is
  templated as `redis://:{{ .auth_token }}@<host>:<port>`.

The resulting Kubernetes `Secret` objects (`database-credentials`,
`redis-credentials`) are created by the external-secrets operator, not by
Terraform — this component only ever references them by name
(`local.database_secret_name`/`local.redis_secret_name`), via `secretKeyRef` in
the Deployments' `env` and the `db-migrate` init container's `envFrom`.

## Redis is optional

Only `fnx-prod-production` runs an `elasticache/main` instance today
(`stacks/catalog/elasticache/defaults.yaml`); dev and staging do not. `redis_enabled`
(default `false`) gates the redis `ExternalSecret`, the `REDIS_URL` env var and
the requirement for `redis_secret_arn`/`redis_host`: dev/staging instances leave
it off, prod's instance turns it on and wires `elasticache/main`'s outputs.

## Images are required, never "latest"

`api_gateway_image`, `platform_api_image`, `auth_service_image` and
`job_processor_image` have no default: a stack must set every one explicitly
(from `settings.environment` or the catalog). Terraform's own "no value for
required variable" error is the failure when one is left unset. Each is also
validated to reject a `:latest` tag, so a stack cannot accidentally deploy an
unpinned image.

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `region`, `environment`, `cluster_name`/`host`/`cluster_ca_certificate` (eks/main outputs), `cluster_secret_store_name` (external-secrets/main output), `database_secret_arn`/`database_endpoint`/`database_name` (rds/main outputs), the 4 `*_image` vars (no `:latest`) | `redis_enabled` (+ `redis_secret_arn`/`redis_host`/`redis_port` when true), `service_versions`, `service_configs`, `enable_prometheus_monitoring`, `enable_database_migrations` | `namespace`, `service_endpoints`, `service_urls`, `deployment_status`, `hpa_status`, `secrets` (Secret *names*, never values) |

## Dependencies & gotchas

- `dependencies.components`: `eks/main`, `eks-addons/main`, `external-secrets/main`,
  `rds/main`, and in prod also `elasticache/main` — every `!terraform.state` target
  above must be declared, and `check-dependencies.py`/`check-deploy-layers.py`
  enforce it.
- `main.tf` and `outputs.tf` read `var.tags["Environment"]` directly, so an
  omitted key would fail at plan/apply with a map-index error. `tags`' own
  validation catches that first, with a clear message.
- `data.aws_eks_cluster_auth` needs real AWS credentials at `apply` time (a
  token, unlike the `exec` plugin, cannot be deferred to `kubectl`'s own AWS
  CLI call) — plan/apply this the same way `alb-controller-ingress-group` is
  planned/applied.
- `kubernetes_deployment_v1`/`kubernetes_horizontal_pod_autoscaler_v2` have no
  `status` block in this provider version (`hashicorp/kubernetes ~> 3.2`) --
  `deployment_status`/`hpa_status` report only the desired-state fields the
  schema actually has (`replicas`/`min_replicas`/`max_replicas`), not live
  rollout counts. An earlier version of this component referenced
  `.status[0].ready_replicas` etc., which does not exist in the schema and
  would fail every plan; that was never caught because the component had no
  tests until this change.
- A Kubernetes object name must be an RFC 1123 subdomain (no `_`), but
  `local.backend_services`' keys (`api_gateway`, `platform_api`, ...) do
  contain one; `local.slug` hyphenates each key wherever it becomes an object
  *name* (Service/Deployment/HPA/PDB/ServiceMonitor/ServiceAccount/ConfigMap
  names, and the `service_urls`/`prometheus_service_monitors` outputs). Labels
  and map keys keep the original underscored key -- only object names are
  slugged.

## Tests

`tests/eks-backend-services.tftest.hcl`, run against mock `aws`/`kubernetes`
providers: `terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan eks-backend-services/main -s fnx-dev-testenv-01
```
