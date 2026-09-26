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
  `fnx-prod-production`'s `rds/main` also sets `master_user_secret_kms_key_id`
  to `kms/main`'s `key_arn` (see the `rds` component's README), matching the
  CMK posture prod uses everywhere else; `external-secrets/main`'s IAM policy
  already grants `kms:Decrypt` on that key, so this component's ExternalSecret
  needed no new grant. Its JSON has `username`/`password` keys; the ExternalSecret's
  `target.template` builds `database_url` as
  `postgres://{{ .username | urlquery }}:{{ .password | urlquery }}@<host:port>/<dbname>`,
  with `<host:port>` (`var.database_endpoint`, `rds/main`'s `instance_endpoint`
  output) and `<dbname>` (`var.database_name`, `instance_name`) as plain,
  non-secret Terraform inputs. `urlquery` (a Go `text/template` builtin ESO's
  template engine exposes) percent-encodes the credential, since RDS-generated
  passwords are not restricted to a URL-safe alphabet.
- **redis** (only when `var.redis_enabled`): `var.redis_secret_arn` is
  `elasticache/main`'s new `auth_token_secret_arn` output (see the elasticache
  component's README — its AUTH token is now also stored in Secrets Manager,
  since `elasticache`'s own `auth_token` input never was). `redis_url` is
  templated as `rediss://:{{ .auth_token | urlquery }}@<host>:<port>` --
  `rediss://` (TLS), never `redis://`: `elasticache`'s own
  `transit_encryption_enabled` validation pins it to `true` for every cache in
  this repo, so the cache only ever accepts TLS connections.

The resulting Kubernetes `Secret` objects (`database-credentials`,
`redis-credentials`) are created by the external-secrets operator, not by
Terraform — this component only ever references them by name
(`local.database_secret_name`/`local.redis_secret_name`), via `secretKeyRef` in
the Deployments' `env` and the `db-migrate` init container's own `env`
(an explicit `secretKeyRef` naming the `database_url` key -- not `envFrom`,
which would expose it as lowercase `database_url`, not the `$DATABASE_URL`
the migration command reads).

## Redis is optional

Only `fnx-prod-production` runs an `elasticache/main` instance today
(`stacks/catalog/elasticache/defaults.yaml`); dev and staging do not. `redis_enabled`
(default `false`) gates the redis `ExternalSecret`, the `REDIS_URL` env var and
the requirement for `redis_secret_arn`/`redis_host`: dev/staging instances leave
it off, prod's instance turns it on and wires `elasticache/main`'s outputs.

## Images are required, never "latest"

`api_gateway_image`, `platform_api_image`, `auth_service_image` and
`job_processor_image` have no default: a stack must set every one explicitly
(from `settings.environment` or the catalog). Each stack's `compute.yaml`
template wraps the lookup in Sprig's `required` (e.g.
`{{ required "settings.environment.backend_service_images.api_gateway must be set" .settings.environment.backend_service_images.api_gateway }}`),
so a missing `backend_service_images` entry fails at template-render time with
a clear message. That alone isn't enough at the Terraform layer: Go's
`text/template` renders a missing map key as the literal string `<no value>`,
which is non-empty and would pass a bare "not blank" check. Each variable's
validation therefore requires the value to actually look like an image
reference — `repository:tag` or `repository@sha256:<digest>` — and separately
rejects a `:latest` tag, so neither an unset stack setting nor an
accidentally-unpinned/untagged image can reach a plan.

Each stack's `backend_service_images` map is release-pipeline-owned (built
elsewhere, not by this repo); `api_gateway` in particular must point at a
real gateway image built to this component's expectations (listens on
`var.api_gateway_image`'s configured `port`, serves `/health`, runs as a
non-root uid) — a stock base image like `nginx` would not, on any of those
points.

## Only `platform_api` runs database migrations

The `db-migrate` init container (`var.enable_database_migrations`, default
`true` in the catalog) is gated to `each.key == "platform_api"` only.
`api_gateway` is a pure reverse proxy with no schema of its own, and its
image is not expected to carry a `migrate` CLI — attaching this init
container there would exit non-zero and leave the pod in
`Init:CrashLoopBackOff` forever.

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
  names, the main container's own `name` inside each Deployment, and the
  `service_urls`/`prometheus_service_monitors` outputs). Labels and map keys
  keep the original underscored key -- only object names (including the
  container name) are slugged.
- `enable_prometheus_monitoring` defaults to `false`: no component in this
  repo installs the Prometheus Operator or its CRDs
  (`monitoring.coreos.com`), and `kubernetes_manifest` resolves a
  `ServiceMonitor`'s schema from the live API server at plan time -- with no
  Operator installed, every plan would fail with "no matches for kind
  ServiceMonitor". Turn it on only once a stack wires an Operator (e.g.
  `kube-prometheus-stack`) into `eks-addons` for that cluster.
- Consumers are wired at the network layer: each stack's `rds/main` sets
  `allowed_security_groups` to `eks/main`'s
  `eks_cluster_managed_security_group_id` (the security group the cluster's
  managed node groups use), and `fnx-prod-production`'s `elasticache/main`
  sets `allowed_security_group_ids` the same way -- otherwise pods on
  `eks/main` cannot reach the database or the cache.
- The default `ClusterSecretStore` (`aws-secretsmanager`) this component's
  ExternalSecrets reference is scoped to this component's own `backend-services`
  namespace via `external-secrets/main`'s `allowed_namespaces` var, so turning
  on `rds_managed_secret_access` there does not let some other namespace on
  the cluster read an RDS-managed master password through the same store.

## Tests

`tests/eks-backend-services.tftest.hcl`, run against mock `aws`/`kubernetes`
providers: `terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan eks-backend-services/main -s fnx-dev-testenv-01
```
