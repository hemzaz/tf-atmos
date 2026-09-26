locals {
  enabled = var.enabled
  # The eks cluster name is already "<Environment>-<name>", so prefixing the
  # Environment again doubled it ("production-production-main-..."). Prefix it
  # only for a cluster name that lacks it, compared case-insensitively as the
  # eks name validation does. Keep in sync with the length validation on
  # var.cluster_name.
  name_prefix = startswith(lower(var.cluster_name), "${lower(var.tags["Environment"])}-") ? var.cluster_name : "${var.tags["Environment"]}-${var.cluster_name}"

  # Secrets Manager and SSM ARNs, scoped to this account/region and to the
  # configured path prefixes: a top-level prefix ("<prefix>/*"), plus, for
  # every var.secret_path_context_prefixes entry, that context nested one
  # level down ("<context>/<prefix>/*"). secretsmanager's full_path nests
  # context_name/environment/path/name (e.g.
  # "production/app/prod/production/app/credentials"), so a bare "*"
  # wildcard there would also match an unrelated secret that merely contains
  # "/<prefix>/" further down its name (e.g. "x/y/app/z"); using the stack's
  # actual context (its descriptive stage name, settings.environment.stage,
  # set in the catalog) instead of "*" keeps the nested match scoped to this
  # stack.
  secretsmanager_resource_arns = concat(
    [
      for prefix in var.secret_path_prefixes :
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${prefix}/*"
    ],
    flatten([
      for context in var.secret_path_context_prefixes : [
        for prefix in var.secret_path_prefixes :
        "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${context}/${prefix}/*"
      ]
    ]),
    # RDS generates "rds!db-<id>" only once the instance exists, so it cannot
    # be a secret_path_prefixes entry (which also rejects "!"); this grants
    # the one fixed naming convention directly instead of a specific ARN.
    var.rds_managed_secret_access ? [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*"
    ] : []
  )

  ssm_resource_arns = concat(
    [
      for prefix in var.ssm_parameter_path_prefixes :
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${prefix}/*"
    ],
    flatten([
      for context in var.secret_path_context_prefixes : [
        for prefix in var.ssm_parameter_path_prefixes :
        "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/${context}/${prefix}/*"
      ]
    ])
  )
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
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = { Name = "${local.name_prefix}-external-secrets-role" }
}

# Create IAM policy for external-secrets to access AWS Secrets Manager
# Rendered from a template (not a static file) so the resource ARNs are
# scoped to this account/region, and to the configured secret path prefixes,
# instead of "arn:aws:secretsmanager:*:*:secret:*". kms:Decrypt is scoped to
# the stack's kms/main key with a kms:ViaService condition.
# secretsmanager:ListSecrets is left on "*": AWS does not support
# resource-level restriction for that action.
resource "aws_iam_policy" "external_secrets" {
  count = local.enabled ? 1 : 0

  name        = "${local.name_prefix}-external-secrets-policy"
  description = "Policy for external-secrets to access AWS Secrets Manager"
  policy = templatefile("${path.module}/policies/external-secrets-policy.json.tpl", {
    region                       = data.aws_region.current.region
    dns_suffix                   = data.aws_partition.current.dns_suffix
    kms_key_arn                  = var.kms_key_arn
    secretsmanager_resource_arns = local.secretsmanager_resource_arns
    ssm_resource_arns            = local.ssm_resource_arns
  })

  tags = { Name = "${local.name_prefix}-external-secrets-policy" }
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

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  set = [
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_secrets[0].arn
    },
  ]

  # Additional customizations can be added here

  depends_on = [
    aws_iam_role.external_secrets,
    aws_iam_policy.external_secrets,
    aws_iam_role_policy_attachment.external_secrets
  ]
}

# Wait for external-secrets CRDs to be registered with dynamic health check
resource "terraform_data" "wait_for_crds" {
  count = local.enabled && (var.create_default_cluster_secret_store || var.create_certificate_secret_store) ? 1 : 0

  depends_on = [helm_release.external_secrets]

  # Use triggers to run on each apply
  triggers_replace = {
    helm_release_id = helm_release.external_secrets[0].id
  }

  # Use local-exec to wait for CRDs to be ready with proper health check
  provisioner "local-exec" {
    command = <<-EOT
      # Maximum wait time in seconds
      MAX_WAIT=120
      # Check interval in seconds
      INTERVAL=5
      # Counter for elapsed time
      ELAPSED=0
      
      echo "Waiting for External Secrets CRDs to be registered..."
      
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        # Check if the CRDs are available and ready
        if kubectl get crd clustersecretstores.external-secrets.io &>/dev/null && \
           kubectl get crd externalsecrets.external-secrets.io &>/dev/null; then
          echo "✅ External Secrets CRDs are registered and available"
          exit 0
        fi
        
        echo "Waiting for CRDs to be available... ($ELAPSED/$MAX_WAIT seconds)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      done
      
      echo "❌ Timed out waiting for External Secrets CRDs"
      echo "Manual intervention may be required"
      # Don't fail the provisioning, as this might be temporary
      exit 0
    EOT
  }
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

  depends_on = [helm_release.external_secrets]
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

  depends_on = [helm_release.external_secrets]
}