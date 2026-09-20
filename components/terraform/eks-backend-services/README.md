# eks-backend-services

Deploys a fixed set of 4 Kubernetes microservices (`api_gateway`, `platform_api`,
`auth_service`, `job_processor`) into a `backend-services` namespace on an existing
EKS cluster: namespace with restricted pod-security labels, a network policy, one
Deployment/Service/ServiceAccount/ConfigMap/HPA/PodDisruptionBudget per service,
write-only `Secret`s for database/redis credentials, and optional Prometheus
`ServiceMonitor`s. Pure Kubernetes-provider component — no AWS resources.

## Deployed instances

Not currently deployed in any of the 3 real stacks (dev, staging, prod) — zero
instances exist today. No stack imports it.

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `environment` (lowercase/hyphen only), `database_url`/`database_password`, `redis_url`/`redis_password` (all `sensitive`+`ephemeral`) | `service_versions`, `service_configs`, `enable_prometheus_monitoring`, `enable_database_migrations` | `namespace`, `service_endpoints`, `service_urls`, `deployment_status`, `hpa_status` |

## Dependencies & gotchas

- No `dependencies.components` entries exist (no instances anywhere); it needs a
  reachable EKS cluster's kubeconfig, configured via Atmos `providers` or
  `KUBE_*` env vars — `provider.tf` wires no AWS/EKS component here.
- `tags` has no validation requiring an `Environment` key (unlike `ec2`/`eks`), but
  `main.tf` and `outputs.tf` read `var.tags["Environment"]` directly — an omitted
  key fails at plan/apply with a map-index error, not a validation message.
- Bump `credentials_revision` to push changed `database_url`/`redis_url`/password
  values — the `data_wo` write-only secrets don't update on their own.
- `platform_api_image`, `auth_service_image`, `job_processor_image` default to
  `<name>:latest` placeholders that don't resolve to real images; override them.

## Usage

A stack must add an instance first. Once added:

```
atmos terraform plan eks-backend-services/main -s fnx-dev-testenv-01
```
