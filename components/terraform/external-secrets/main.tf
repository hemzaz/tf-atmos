locals {
  enabled = var.enabled
  # The eks cluster name is already "<Environment>-<name>", so prefixing the
  # Environment again doubled it ("production-production-main-..."). Prefix it
  # only for a cluster name that lacks it, compared case-insensitively as the
  # eks name validation does. Keep in sync with the length validation on
  # var.cluster_name.
  name_prefix = startswith(lower(var.cluster_name), "${lower(var.tags["Environment"])}-") ? var.cluster_name : "${var.tags["Environment"]}-${var.cluster_name}"

  # One ClusterSecretStore per entry, each with its own service account and
  # IRSA role reading only the secrets it serves, and usable only from its own
  # namespaces. The key is both the store's and its service account's name.
  stores = {
    "aws-secretsmanager" = {
      create      = var.create_default_cluster_secret_store
      role_suffix = "external-secrets"
      prefixes    = var.secret_path_prefixes
      rds         = var.rds_managed_secret_access
      namespaces  = var.allowed_namespaces
    }
    "aws-certificate-store" = {
      create      = var.create_certificate_secret_store
      role_suffix = "external-secrets-cert"
      prefixes    = var.certificate_secret_path_prefixes
      rds         = false
      namespaces  = var.certificate_allowed_namespaces
    }
  }
  enabled_stores = { for k, v in local.stores : k => v if local.enabled && v.create }

  secret_arn_prefix = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:"

  # Per store: "<prefix>/*" plus "<context>/<prefix>/*" for every
  # var.secret_path_context_prefixes entry. secretsmanager's full_path nests
  # context_name/environment/path/name (e.g.
  # "production/app/prod/production/app/credentials"), so a "*/<prefix>/*"
  # wildcard would also match an unrelated secret containing "/<prefix>/"
  # further down; the stack's own context (settings.environment.stage, set in
  # the catalog) keeps the nested match scoped. RDS generates "rds!db-<id>"
  # only once the instance exists, so rds_managed_secret_access grants that
  # fixed naming convention directly ("!" is not a valid prefix entry).
  store_secret_arns = {
    for k, v in local.enabled_stores : k => concat(
      [for prefix in v.prefixes : "${local.secret_arn_prefix}${prefix}/*"],
      flatten([
        for context in var.secret_path_context_prefixes : [
          for prefix in v.prefixes : "${local.secret_arn_prefix}${context}/${prefix}/*"
        ]
      ]),
      v.rds ? ["${local.secret_arn_prefix}rds!db-*"] : []
    )
  }
}

# IRSA role per store, trusted only by that store's service account.
resource "aws_iam_role" "external_secrets" {
  for_each = local.enabled_stores

  name = "${local.name_prefix}-${each.value.role_suffix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${each.key}"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = { Name = "${local.name_prefix}-${each.value.role_suffix}-role" }
}

# Secrets Manager reads on the store's own ARN prefixes only, in this
# account/region, and kms:Decrypt on the stack's kms/main key through Secrets
# Manager only. No secretsmanager:ListSecrets: it has no resource-level
# support (it would need "*") and ESO needs it only for dataFrom.find, which
# nothing here uses.
resource "aws_iam_policy" "external_secrets" {
  for_each = local.enabled_stores

  name        = "${local.name_prefix}-${each.value.role_suffix}-policy"
  description = "external-secrets ClusterSecretStore ${each.key}: read its Secrets Manager paths"
  policy = templatefile("${path.module}/policies/external-secrets-policy.json.tpl", {
    region                       = data.aws_region.current.region
    dns_suffix                   = data.aws_partition.current.dns_suffix
    kms_key_arn                  = var.kms_key_arn
    secretsmanager_resource_arns = local.store_secret_arns[each.key]
  })

  tags = { Name = "${local.name_prefix}-${each.value.role_suffix}-policy" }
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  for_each = local.enabled_stores

  role       = aws_iam_role.external_secrets[each.key].name
  policy_arn = aws_iam_policy.external_secrets[each.key].arn
}

# The operator and its CRDs. Its own service account has no IRSA role: a
# namespaced SecretStore with no auth block would read with the operator's
# credentials, bypassing the stores' namespace conditions.
resource "helm_release" "external_secrets" {
  count = local.enabled ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = [
    yamlencode({
      installCRDs = true
      serviceAccount = {
        create = true
        name   = var.service_account_name
      }
    }),
  ]

  # The stores release below needs the CRDs and the validating webhook up.
  wait    = true
  atomic  = true
  timeout = 600
}

# The ClusterSecretStores and their service accounts, from a local chart
# installed after the operator, so the first plan does not need the
# external-secrets CRDs (a kubernetes_manifest would). Cloud Posse's
# eks/external-secrets-operator installs its store the same way
# (charts/external-ssm-secrets, a second helm release).
resource "helm_release" "cluster_secret_stores" {
  count = length(local.enabled_stores) > 0 ? 1 : 0

  name      = "external-secrets-stores"
  chart     = "${path.module}/charts/cluster-secret-stores"
  namespace = var.namespace
  # Referencing the operator release orders this after it (with depends_on).
  description = "ClusterSecretStores for ${helm_release.external_secrets[0].name} ${helm_release.external_secrets[0].version}"

  values = [
    yamlencode({
      region = var.region
      stores = [
        for k, v in local.enabled_stores : {
          name       = k
          roleArn    = aws_iam_role.external_secrets[k].arn
          namespaces = v.namespaces
        }
      ]
    }),
  ]

  wait    = true
  atomic  = true
  timeout = 300

  depends_on = [
    helm_release.external_secrets,
    aws_iam_role_policy_attachment.external_secrets,
  ]
}
