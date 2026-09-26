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
  api_gateway_image         = "nginx:1.25-alpine"
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
