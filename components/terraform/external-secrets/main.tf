locals {
  enabled = var.enabled
  name_prefix = "${var.tags["Environment"]}-${var.cluster_name}"
}

# Create IAM role for external-secrets to access AWS Secrets Manager
resource "aws_iam_role" "external_secrets" {
  count = local.enabled ? 1 : 0

  name = "${local.name_prefix}-external-secrets-role"

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
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-external-secrets-role"
    }
  )
}

# Create IAM policy for external-secrets to access AWS Secrets Manager
resource "aws_iam_policy" "external_secrets" {
  count = local.enabled ? 1 : 0

  name        = "${local.name_prefix}-external-secrets-policy"
  description = "Policy for external-secrets to access AWS Secrets Manager"
  policy      = file("${path.module}/policies/external-secrets-policy.json")

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-external-secrets-policy"
    }
  )
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "external_secrets" {
  count = local.enabled ? 1 : 0

  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}

# Install external-secrets with Helm
resource "helm_release" "external_secrets" {
  count = local.enabled ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version
  namespace  = var.namespace
  create_namespace = var.create_namespace

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.service_account_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets[0].arn
  }

  # Additional customizations can be added here

  depends_on = [
    aws_iam_role.external_secrets,
    aws_iam_policy.external_secrets,
    aws_iam_role_policy_attachment.external_secrets
  ]
}

# Wait for external-secrets CRDs to be registered
resource "time_sleep" "wait_for_crds" {
  count = local.enabled && (var.create_default_cluster_secret_store || var.create_certificate_secret_store) ? 1 : 0

  depends_on = [helm_release.external_secrets]
  create_duration = "30s"
}

# Create ClusterSecretStore for AWS Secrets Manager
resource "kubernetes_manifest" "cluster_secret_store" {
  count = local.enabled && var.create_default_cluster_secret_store ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = var.service_account_name
                namespace = var.namespace
              }
            }
          }
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_crds]
}

# Create a dedicated ClusterSecretStore for certificate secrets
resource "kubernetes_manifest" "certificate_secret_store" {
  count = local.enabled && var.create_certificate_secret_store ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-certificate-store"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = var.service_account_name
                namespace = var.namespace
              }
            }
          }
        }
      }
    }
  }

  depends_on = [time_sleep.wait_for_crds]
}