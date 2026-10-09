# eks-backend-services

Deploys four fixed microservices (`api_gateway`, `platform_api`, `auth_service`, `job_processor`)
into a `backend-services` namespace: restricted pod-security labels, a network policy, a
Deployment/Service/ServiceAccount/ConfigMap/HPA/PDB per service, `ExternalSecret`s for database and
Redis credentials, and optional Prometheus `ServiceMonitor`s.

## Wiring

- Instance: `eks-backend-services/main` in the three AWS stacks, `fnx-ue2-prod` (`enabled: false`
  until failover) and `fnx-ew1-prod`, on `eks/main`, in the `services` layer; `fnx-ue1-prod`'s and
  `fnx-ew1-prod`'s inherit `eks-backend-services/prod`
  (`stacks/catalog/eks-backend-services/prod.yaml`).
- Reads: `eks/main` (cluster ID, endpoint, CA), `external-secrets/main
  .default_cluster_secret_store_name`, `rds/main .password_secret_arn` / `.instance_endpoint` /
  `.instance_name`; in prod also `elasticache/main .auth_token_secret_arn` /
  `.primary_endpoint_address` / `.port` (`redis_enabled`).
- Also depends on `eks-addons/main`.

## Notes

- Credentials never pass through Terraform: the ExternalSecrets pull the RDS-managed master secret
  and the ElastiCache AUTH token from Secrets Manager and template `database_url` (`postgres://`)
  and `redis_url` (`rediss://`, TLS only).
- `database_url` carries `sslmode=verify-full&sslrootcert=<database_ca_bundle_path>`: `rds` forces
  TLS, so every service image (and `platform_api`'s, which also runs `migrate`) must ship the RDS
  CA bundle (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`) at that path,
  default `/etc/ssl/certs/rds-global-bundle.pem`. Without it the services cannot connect.
- The four `*_image` inputs have no default, must look like `repo:tag` or `repo@sha256:...`, and
  reject `:latest`. The stacks take them from `settings.environment.backend_service_images`, which
  the release pipeline owns.
- Only `platform_api` runs the `db-migrate` init container.
- Uses `data.aws_eks_cluster_auth` for the provider token (no `aws` CLI in the CI image), so apply
  needs real AWS credentials and, with private endpoints, network access to the cluster.
- `enable_prometheus_monitoring` stays `false` until a stack installs the Prometheus Operator: the
  `ServiceMonitor` schema is resolved from the live API at plan time.
- `deployment_status` / `hpa_status` report desired replicas only; the provider exposes no live status.
- Pods reach the database and cache because `rds/main` and prod's `elasticache/main` admit
  `eks/main .eks_cluster_managed_security_group_id`.
