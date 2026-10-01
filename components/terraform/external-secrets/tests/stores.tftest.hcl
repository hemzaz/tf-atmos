# Mock-provider tests of the ClusterSecretStores (charts/cluster-secret-stores),
# their per-store IRSA roles and namespace conditions, and the release
# ordering. No AWS or cluster access. apply, not plan: the stores' values embed
# the role ARNs, which mocks only generate on apply.

mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-2"
    }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
  override_data {
    target = data.aws_partition.current
    values = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
  # The attachment validates ARNs; mocks otherwise generate random strings.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
}
mock_provider "helm" {}

variables {
  region                    = "eu-west-2"
  cluster_name              = "production-main"
  host                      = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate    = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  oidc_provider_arn         = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  oidc_provider_url         = "https://oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  kms_key_arn               = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  allowed_namespaces        = ["backend-services"]
  rds_managed_secret_access = true
  tags = {
    Environment = "production"
  }
}

# The stores release installs after the operator: it references the operator
# release (and depends_on it), so Terraform cannot create it first.
run "stores_release_follows_the_operator" {
  command = apply

  assert {
    condition     = helm_release.cluster_secret_stores[0].description == "ClusterSecretStores for external-secrets 2.11.0"
    error_message = "The stores release must reference the operator release (name and version), which orders it after the operator."
  }

  assert {
    condition     = endswith(helm_release.cluster_secret_stores[0].chart, "/charts/cluster-secret-stores") && helm_release.cluster_secret_stores[0].namespace == "external-secrets"
    error_message = "The stores come from the local chart, in the operator's namespace."
  }

  assert {
    condition     = helm_release.external_secrets[0].version == "2.11.0" && helm_release.external_secrets[0].wait
    error_message = "The operator is chart 2.11.0 and waits for its CRDs and webhook before the stores release starts."
  }

  # The operator's own service account carries no role: a namespaced
  # SecretStore without auth would otherwise read with it.
  assert {
    condition     = !strcontains(helm_release.external_secrets[0].values[0], "role-arn")
    error_message = "The operator's service account must not be annotated with an IRSA role."
  }
}

run "store_conditions_and_service_accounts_are_rendered" {
  command = apply

  assert {
    condition = {
      for s in yamldecode(helm_release.cluster_secret_stores[0].values[0]).stores : s.name => s.namespaces
      } == {
      "aws-secretsmanager"    = ["backend-services"]
      "aws-certificate-store" = ["istio-ingress"]
    }
    error_message = "Each store must be limited to its own namespaces: aws-secretsmanager to allowed_namespaces, aws-certificate-store to certificate_allowed_namespaces."
  }

  assert {
    condition = alltrue([
      for s in yamldecode(helm_release.cluster_secret_stores[0].values[0]).stores : s.roleArn == aws_iam_role.external_secrets[s.name].arn
    ])
    error_message = "Each store's service account must carry its own IRSA role."
  }

  assert {
    condition = alltrue([
      for k, r in aws_iam_role.external_secrets : jsondecode(r.assume_role_policy).Statement[0].Condition.StringEquals == {
        "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:sub" = "system:serviceaccount:external-secrets:${k}"
        "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:aud" = "sts.amazonaws.com"
      }
    ]) && length(aws_iam_role.external_secrets) == 2
    error_message = "Each role must trust exactly its store's service account (sub) for sts.amazonaws.com (aud)."
  }
}

# Least privilege: each store's policy names only its own secret ARN prefixes,
# never "*", and the certificate store reads nothing but certificates.
run "store_policies_are_scoped" {
  command = apply

  variables {
    secret_path_context_prefixes = ["production"]
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_policy.external_secrets : !contains(flatten([for s in jsondecode(p.policy).Statement : s.Resource]), "*")
    ])
    error_message = "No statement may use Resource \"*\"."
  }

  assert {
    condition = alltrue(flatten([
      for k, p in aws_iam_policy.external_secrets : [
        for s in jsondecode(p.policy).Statement : [
          for a in s.Action : !startswith(a, "ssm:") && a != "secretsmanager:ListSecrets"
        ]
      ]
    ]))
    error_message = "No store reads SSM or lists secrets."
  }

  assert {
    condition = toset(jsondecode(aws_iam_policy.external_secrets["aws-certificate-store"].policy).Statement[0].Resource) == toset([
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:certificates/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:production/certificates/*",
    ])
    error_message = "The certificate store's role must read only certificates/* and <context>/certificates/*."
  }

  assert {
    condition = toset(jsondecode(aws_iam_policy.external_secrets["aws-secretsmanager"].policy).Statement[0].Resource) == toset([
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:app/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:infra/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:redis-auth/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:production/app/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:production/infra/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:production/redis-auth/*",
      "arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds!db-*",
    ])
    error_message = "The default store's role must read exactly app, infra, redis-auth (top-level and <context>/) and rds!db-*: no certificates, no ssh-key."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.external_secrets["aws-certificate-store"].policy).Statement[1].Resource == var.kms_key_arn
    error_message = "kms:Decrypt must be on the stack's key only."
  }
}

run "a_disabled_store_gets_no_role_or_entry" {
  command = apply

  variables {
    create_certificate_secret_store = false
  }

  assert {
    condition     = keys(aws_iam_role.external_secrets) == ["aws-secretsmanager"] && length(yamldecode(helm_release.cluster_secret_stores[0].values[0]).stores) == 1
    error_message = "With create_certificate_secret_store = false, neither its role nor its store may exist."
  }
}

run "no_stores_means_no_stores_release" {
  command = plan

  variables {
    create_default_cluster_secret_store = false
    create_certificate_secret_store     = false
    allowed_namespaces                  = []
  }

  assert {
    condition     = length(helm_release.cluster_secret_stores) == 0 && length(aws_iam_role.external_secrets) == 0 && length(helm_release.external_secrets) == 1
    error_message = "With both stores off, only the operator is installed."
  }
}

run "empty_allowed_namespaces_is_rejected" {
  command = plan

  variables {
    allowed_namespaces = []
  }

  expect_failures = [var.allowed_namespaces]
}

run "wildcard_allowed_namespace_is_rejected" {
  command = plan

  variables {
    allowed_namespaces = ["*"]
  }

  expect_failures = [var.allowed_namespaces]
}

run "invalid_certificate_namespace_is_rejected" {
  command = plan

  variables {
    certificate_allowed_namespaces = ["Istio_Ingress"]
  }

  expect_failures = [var.certificate_allowed_namespaces]
}

run "certificates_in_the_default_store_are_rejected" {
  command = plan

  variables {
    secret_path_prefixes = ["app", "certificates"]
  }

  expect_failures = [var.secret_path_prefixes]
}

run "ssh_key_in_the_default_store_is_rejected" {
  command = plan

  variables {
    secret_path_prefixes = ["app", "ssh-key"]
  }

  expect_failures = [var.secret_path_prefixes]
}

run "a_v1beta1_era_chart_is_rejected" {
  command = plan

  variables {
    chart_version = "0.9.9"
  }

  expect_failures = [var.chart_version]
}
