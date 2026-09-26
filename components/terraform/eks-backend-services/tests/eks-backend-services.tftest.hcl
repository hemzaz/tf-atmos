# Mock-provider tests: no AWS credentials, no cluster access. Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_data {
    target = data.aws_eks_cluster_auth.this
    values = {
      token = "mock-token"
    }
  }
}

mock_provider "kubernetes" {}

variables {
  region                    = "eu-west-2"
  environment               = "dev"
  cluster_name              = "testenv-01-main"
  host                      = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate    = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  cluster_secret_store_name = "aws-secretsmanager"
  database_secret_arn       = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds!db-11111111-2222-3333-4444-555555555555"
  database_endpoint         = "testenv-01-main-db.abcdefghijk.eu-west-2.rds.amazonaws.com:5432"
  database_name             = "mainapp"
  api_gateway_image         = "ghcr.io/fnx-platform/api-gateway:1.4.2"
  platform_api_image        = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/platform-api:1.4.2"
  auth_service_image        = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/auth-service:1.4.2"
  job_processor_image       = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/job-processor:1.4.2"
  tags = {
    Environment = "dev"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "database_external_secret_targets_the_shared_store" {
  command = plan

  assert {
    condition     = kubernetes_manifest.database_external_secret.manifest.spec.secretStoreRef.name == "aws-secretsmanager"
    error_message = "The database ExternalSecret must reference the shared ClusterSecretStore by name."
  }

  assert {
    condition     = kubernetes_manifest.database_external_secret.manifest.spec.secretStoreRef.kind == "ClusterSecretStore"
    error_message = "secretStoreRef.kind must be ClusterSecretStore, not the namespaced SecretStore."
  }

  assert {
    condition     = kubernetes_manifest.database_external_secret.manifest.spec.target.name == "database-credentials"
    error_message = "The target Secret must be named database-credentials -- what the Deployments' secretKeyRef and the db-migrate init container's envFrom reference."
  }
}

run "redis_is_off_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.redis_external_secret) == 0
    error_message = "redis_enabled defaults to false (dev/staging run no elasticache instance); no redis ExternalSecret should be created."
  }

  assert {
    condition = !contains(
      [for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].container[0].env : e.name],
      "REDIS_URL"
    )
    error_message = "REDIS_URL must not be injected when redis_enabled is false."
  }
}

run "redis_enabled_creates_its_own_external_secret_and_env_var" {
  command = plan

  variables {
    redis_enabled    = true
    redis_secret_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:redis-auth/production/production-cache-AbCdEf"
    redis_host       = "production-cache.abcdefg.euw2.cache.amazonaws.com"
  }

  assert {
    condition     = length(kubernetes_manifest.redis_external_secret) == 1
    error_message = "redis_enabled must create exactly one redis ExternalSecret."
  }

  assert {
    condition     = kubernetes_manifest.redis_external_secret[0].manifest.spec.secretStoreRef.name == "aws-secretsmanager"
    error_message = "The redis ExternalSecret must reference the shared ClusterSecretStore by name."
  }

  assert {
    condition = contains(
      [for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].container[0].env : e.name],
      "REDIS_URL"
    )
    error_message = "REDIS_URL must be injected when redis_enabled is true."
  }
}

run "no_plaintext_credential_reaches_the_deployment_spec" {
  command = plan

  # DATABASE_URL/REDIS_URL are always sourced via secretKeyRef (value_from),
  # never a literal `value` -- credentials only ever flow from Secrets
  # Manager, through the ExternalSecret, into the cluster; this component
  # takes no database_password/redis_password (or similar) variable at all.
  variables {
    redis_enabled    = true
    redis_secret_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:redis-auth/dev/dev-cache-AbCdEf"
    redis_host       = "dev-cache.abcdefg.euw2.cache.amazonaws.com"
  }

  assert {
    condition = alltrue([
      for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].container[0].env :
      e.name != "DATABASE_URL" || e.value == null
    ])
    error_message = "DATABASE_URL must never carry a literal value."
  }

  assert {
    condition = alltrue([
      for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].container[0].env :
      e.name != "REDIS_URL" || e.value == null
    ])
    error_message = "REDIS_URL must never carry a literal value."
  }
}

run "images_reject_a_latest_tag" {
  command = plan

  variables {
    platform_api_image = "platform-api:latest"
  }

  expect_failures = [
    var.platform_api_image,
  ]
}

# An untagged reference implicitly pulls ":latest" from the registry; the
# variable must require an explicit tag or @sha256 digest.
run "images_reject_an_untagged_reference" {
  command = plan

  variables {
    api_gateway_image = "nginx"
  }

  expect_failures = [
    var.api_gateway_image,
  ]
}

# Go's text/template renders a missing map key (e.g. an unset
# settings.environment.backend_service_images.* entry, before the stack
# templates added their own `required` guard) as the literal string
# "<no value>" -- non-empty, so a plain "not blank" check would miss it. The
# regex must reject it outright.
run "images_reject_the_go_template_missing_key_sentinel" {
  command = plan

  variables {
    auth_service_image = "<no value>"
  }

  expect_failures = [
    var.auth_service_image,
  ]
}

# Container names must be DNS-1123 labels (lowercase alphanumeric and "-",
# no "_"): local.backend_services' keys (api_gateway, ...) are not, so the
# container name must come from local.slug, never each.key directly.
run "container_names_are_dns_1123_compliant" {
  command = plan

  assert {
    condition = alltrue([
      for k, d in kubernetes_deployment_v1.backend_services :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", d.spec[0].template[0].spec[0].container[0].name))
    ])
    error_message = "Every container name must be a DNS-1123 label (lowercase alphanumeric and '-', no '_')."
  }
}

# The db-migrate init container's `migrate ... -database $DATABASE_URL`
# reads the DATABASE_URL env var by that exact name; env_from would expose
# the target Secret's lowercase "database_url" key instead.
run "init_container_exposes_database_url_by_name" {
  command = plan

  assert {
    condition = contains(
      [for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].init_container[0].env : e.name],
      "DATABASE_URL"
    )
    error_message = "The db-migrate init container must expose an env var named exactly DATABASE_URL."
  }

  assert {
    condition = alltrue([
      for e in kubernetes_deployment_v1.backend_services["platform_api"].spec[0].template[0].spec[0].init_container[0].env :
      e.name != "DATABASE_URL" || e.value == null
    ])
    error_message = "DATABASE_URL must never carry a literal value in the init container either."
  }
}

# api_gateway is a pure reverse proxy with no schema of its own -- only
# platform_api owns the database and runs `migrate`. api_gateway's image is
# also a release-pipeline-owned gateway image, not a Go binary with a
# `migrate` CLI baked in, so an init container there would exit 127.
run "api_gateway_runs_no_migration_init_container" {
  command = plan

  assert {
    condition     = length(kubernetes_deployment_v1.backend_services["api_gateway"].spec[0].template[0].spec[0].init_container) == 0
    error_message = "api_gateway's Deployment must not have a db-migrate init container."
  }
}

# elasticache/main's transit_encryption_enabled is pinned to true for every
# cache in this repo, so the cache only ever accepts TLS.
run "redis_url_uses_the_tls_scheme" {
  command = plan

  variables {
    redis_enabled    = true
    redis_secret_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:redis-auth/dev/dev-cache-AbCdEf"
    redis_host       = "dev-cache.abcdefg.euw2.cache.amazonaws.com"
  }

  assert {
    condition     = startswith(kubernetes_manifest.redis_external_secret[0].manifest.spec.target.template.data.redis_url, "rediss://")
    error_message = "redis_url must use the rediss:// (TLS) scheme, never redis://."
  }
}
