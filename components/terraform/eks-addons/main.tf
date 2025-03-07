# ============================================================================
# EKS Addons Component - Main Configuration
# ============================================================================
# This component deploys AWS EKS addons, Helm charts, and Kubernetes manifests
# to EKS clusters. It supports multiple clusters concurrently.
# ============================================================================

locals {
  # -------------------------------------------------------------
  # Step 1: Filter enabled clusters
  # -------------------------------------------------------------
  # Only process clusters where enabled=true (or not specified)
  clusters = {
    for k, v in var.clusters : k => v if lookup(v, "enabled", true)
  }

  # -------------------------------------------------------------
  # Step 2: Create flattened maps for addons, Helm releases, and
  # Kubernetes manifests, preserving cluster context
  # -------------------------------------------------------------
  # For each resource type, we:
  # 1. Loop through each cluster
  # 2. Extract all resources of that type from the cluster
  # 3. Add the cluster_name to each resource for context
  # 4. Create a composite key (cluster_key.resource_key) to ensure uniqueness
  # 5. Skip any resources with enabled=false
  # -------------------------------------------------------------

  # Flatten addons across all clusters
  # Result: { "cluster1.addon1" => {name: "addon1", cluster_name: "cluster1", ...}, ... }
  addons = merge([
    for cluster_key, cluster in local.clusters : {
      for addon_key, addon in lookup(cluster, "addons", {}) :
      "${cluster_key}.${addon_key}" => merge(addon, { cluster_name = cluster_key })
      if lookup(addon, "enabled", true)
    }
  ]...)

  # Flatten Helm releases across all clusters 
  # Same pattern as addons - composite keys with cluster context added to each release
  helm_releases = merge([
    for cluster_key, cluster in local.clusters : {
      for release_key, release in lookup(cluster, "helm_releases", {}) :
      "${cluster_key}.${release_key}" => merge(release, { cluster_name = cluster_key })
      if lookup(release, "enabled", true)
    }
  ]...)

  # Flatten Kubernetes manifests across all clusters
  # Same pattern as above - consistent approach for all resource types
  kubernetes_manifests = merge([
    for cluster_key, cluster in local.clusters : {
      for manifest_key, manifest in lookup(cluster, "kubernetes_manifests", {}) :
      "${cluster_key}.${manifest_key}" => merge(manifest, { cluster_name = cluster_key })
      if lookup(manifest, "enabled", true)
    }
  ]...)

  # Certificate handling: ACM certificates are integrated with Istio
  # The certificate is either:
  # 1. Loaded directly (legacy mode using acm_certificate_key/acm_certificate_crt)
  # 2. Managed by External Secrets (recommended approach using Secrets Manager)

  # Template for Istio gateway configurations
  istio_gateway_template = templatefile(
    "${path.module}/kubernetes_manifests/istio-gateway.yaml",
    {
      domain_name = var.domain_name
    }
  )
}

# Get cluster info to validate it's accessible before proceeding
data "aws_eks_cluster" "this" {
  for_each = local.clusters
  name     = each.key
}

# Wait for EKS cluster to be fully ready with health check
# Create a dynamic wait using time_sleep resource instead of null_resource with local-exec
# This removes dependency on local tools and shell scripting
resource "time_sleep" "wait_for_cluster" {
  for_each = local.clusters

  depends_on = [
    data.aws_eks_cluster.this
  ]

  # Ensure this always runs by using triggers
  triggers = {
    cluster_name     = each.key
    cluster_endpoint = data.aws_eks_cluster.this[each.key].endpoint
    # Add hash of cluster status to detect changes
    cluster_status   = data.aws_eks_cluster.this[each.key].status
  }

  # Set a base wait time that can be overridden per cluster
  create_duration = lookup(each.value, "wait_for_cluster_duration", "45s")

  # Add validation to ensure cluster is actually ACTIVE
  lifecycle {
    postcondition {
      condition     = data.aws_eks_cluster.this[each.key].status == "ACTIVE"
      error_message = "EKS cluster ${each.key} is not in ACTIVE state after waiting. Current status: ${data.aws_eks_cluster.this[each.key].status}"
    }
  }
}

# Create IAM service account roles for addons if needed
resource "aws_iam_role" "service_account" {
  for_each = {
    for k, v in local.addons : k => v
    if lookup(v, "create_service_account_role", false)
  }

  name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = lookup(each.value, "oidc_provider_arn", var.oidc_provider_arn)
        }
        Condition = {
          StringEquals = {
            "${replace(lookup(each.value, "oidc_provider_url", var.oidc_provider_url), "https://", "")}:sub" = "system:serviceaccount:${lookup(each.value, "namespace", "kube-system")}:${lookup(each.value, "service_account_name", each.value.name)}"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}-sa-role"
    }
  )
}

resource "aws_iam_policy" "service_account" {
  for_each = {
    for k, v in local.addons : k => v
    if lookup(v, "create_service_account_role", false) && lookup(v, "service_account_policy", null) != null
  }

  name        = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}-sa-policy"
  description = "Policy for ${each.value.name} service account in ${each.value.cluster_name} cluster"
  policy      = each.value.service_account_policy

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}-sa-policy"
    }
  )
}

resource "aws_iam_role_policy_attachment" "service_account" {
  for_each = {
    for k, v in aws_iam_policy.service_account : k => {
      role_name  = aws_iam_role.service_account[k].name
      policy_arn = v.arn
    }
  }

  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}

# AWS EKS Addons
resource "aws_eks_addon" "addons" {
  for_each = local.addons

  cluster_name      = each.value.cluster_name
  addon_name        = each.value.name
  addon_version     = lookup(each.value, "version", null)
  resolve_conflicts = lookup(each.value, "resolve_conflicts", "OVERWRITE")

  # Fix circular dependency by directly using service_account_role_arn if provided,
  # otherwise set to null and establish depends_on relationship
  service_account_role_arn = lookup(each.value, "service_account_role_arn", null)

  preserve = lookup(each.value, "preserve", true)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}"
    }
  )

  # Add dependency on wait_for_cluster and conditionally on service account role
  depends_on = concat(
    [time_sleep.wait_for_cluster],
    lookup(each.value, "create_service_account_role", false) &&
    contains(keys(aws_iam_role_policy_attachment.service_account), "${each.value.cluster_name}.${each.value.name}") ?
    [aws_iam_role_policy_attachment.service_account["${each.value.cluster_name}.${each.value.name}"]] : []
  )
}

# Wait for addons to be ready before proceeding with helm releases
# Replace complex null_resource with proper Terraform time_sleep resource
resource "time_sleep" "wait_for_addons" {
  count = length(local.addons) > 0 ? 1 : 0

  depends_on = [
    aws_eks_addon.addons,
    aws_iam_role_policy_attachment.service_account
  ]

  # Generate a hash of all addon attributes to detect changes
  triggers = {
    addon_hash = sha256(jsonencode([
      for k, v in aws_eks_addon.addons : {
        id = v.id
        status = v.status
        addon_version = v.addon_version
      }
    ]))
  }

  # Set reasonable wait time for addons to be ready
  create_duration = "3m"

  # Add validation to catch addon creation issues
  lifecycle {
    postcondition {
      condition     = length(aws_eks_addon.addons) > 0
      error_message = "No EKS addons were created. Check that the addons configuration is correct."
    }
  }
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    host                   = var.host
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

# Helm Releases
resource "helm_release" "releases" {
  for_each = local.helm_releases

  name             = lookup(each.value, "release_name", each.key)
  chart            = each.value.chart
  repository       = lookup(each.value, "repository", null)
  version          = lookup(each.value, "chart_version", null)
  namespace        = lookup(each.value, "namespace", "default")
  create_namespace = lookup(each.value, "create_namespace", true)

  values = lookup(each.value, "values", [])

  # Only set clusterName if not provided by user
  dynamic "set" {
    for_each = contains(keys(lookup(each.value, "set_values", {})), "clusterName") ? [] : [1]
    content {
      name  = "clusterName"
      value = each.value.cluster_name
    }
  }

  dynamic "set" {
    for_each = lookup(each.value, "set_values", {})
    content {
      name  = set.key
      value = set.value
    }
  }

  dynamic "set_sensitive" {
    for_each = lookup(each.value, "set_sensitive_values", {})
    content {
      name  = set_sensitive.key
      value = set_sensitive.value
    }
  }

  timeout = lookup(each.value, "timeout", 300)
  atomic  = lookup(each.value, "atomic", true)
  wait    = lookup(each.value, "wait", true)

  # Wait for addons and service accounts to be created
  depends_on = [
    time_sleep.wait_for_addons,
    aws_iam_role_policy_attachment.service_account,
    time_sleep.wait_for_cluster
  ]
}

# Wait for helm releases to be ready before proceeding with kubernetes manifests
# Replace complicated null_resource with simpler time_sleep approach
resource "time_sleep" "wait_for_helm_releases" {
  count = length(local.helm_releases) > 0 ? 1 : 0

  depends_on = [
    helm_release.releases
  ]

  # Generate a detailed hash of all helm releases with relevant attributes to detect changes
  triggers = {
    # Include version, values hash, and status to ensure sensitivity to real changes
    releases_hash = sha256(jsonencode([
      for k, v in helm_release.releases : {
        id = v.id
        name = v.name
        version = v.version
        namespace = v.namespace
        values_hash = v.metadata[0].values_hash
        status = v.status
      }
    ]))
    releases_count = length(helm_release.releases)
  }

  # Set a reasonable wait time for Helm releases to stabilize
  # Use a dynamic duration based on the number of releases (min 2m, max 5m)
  create_duration = "${min(max(2 * length(local.helm_releases), 120), 300)}s"
  
  # Add validation for helm releases
  lifecycle {
    postcondition {
      condition     = length(helm_release.releases) > 0
      error_message = "No Helm releases were created. Check the helm_releases configuration."
    }
  }
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = var.host
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}

# Kubernetes Manifests
resource "kubernetes_manifest" "manifests" {
  for_each = local.kubernetes_manifests

  manifest = each.value.manifest

  field_manager {
    name            = lookup(each.value, "field_manager_name", "${var.tags["Environment"]}-${each.value.cluster_name}")
    force_conflicts = lookup(each.value, "force_conflicts", true)
  }

  depends_on = [
    time_sleep.wait_for_cluster,
    time_sleep.wait_for_helm_releases
  ]
}

# Apply Istio gateway configuration
resource "kubectl_manifest" "istio_gateway" {
  count             = var.domain_name != "" && var.istio_enabled ? 1 : 0
  yaml_body         = local.istio_gateway_template
  wait              = true
  server_side_apply = true
  force_conflicts   = true
  wait_for_rollout  = true

  depends_on = [
    helm_release.releases,
    time_sleep.wait_for_helm_releases
  ]

  # Add timeout to ensure adequate time for manifest creation
  timeouts {
    create = "5m"
    update = "5m"
    delete = "3m"
  }
}

# Wait for istio-ingress namespace to be ready before proceeding with certificate-related resources
resource "time_sleep" "wait_for_istio_namespace" {
  count = var.istio_enabled ? 1 : 0

  depends_on = [
    time_sleep.wait_for_helm_releases,
    kubectl_manifest.istio_gateway
  ]

  # Increase wait time to ensure namespace is fully ready with all resources
  create_duration = "45s"
}

# Create a Kubernetes secret from ACM certificate content
resource "kubernetes_secret" "istio_certs" {
  count = var.istio_enabled && !var.use_external_secrets && var.acm_certificate_crt != "" && var.acm_certificate_key != "" ? 1 : 0

  metadata {
    name      = "istio-gateway-cert"
    namespace = "istio-ingress"
  }

  data = {
    "tls.crt" = var.acm_certificate_crt
    "tls.key" = var.acm_certificate_key
  }

  type = "kubernetes.io/tls"

  depends_on = [
    time_sleep.wait_for_istio_namespace
  ]
}

# External Secrets Integration
#
# IMPORTANT: The external-secrets operator is deployed via a separate component (external-secrets)
# This just creates the ExternalSecret resource that connects to that operator
#
# When using this approach, make sure to:
# 1. Deploy the external-secrets component first (it's a dependency)
# 2. Store your certificates in AWS Secrets Manager using the scripts in /scripts/certificates
# 3. Set use_external_secrets: true in your configuration

resource "kubernetes_manifest" "istio_certificate_external_secret" {
  count = var.istio_enabled && var.use_external_secrets && var.secrets_manager_secret_path != "" ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "istio-certificate"
      namespace = "istio-ingress"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-certificate-store"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "istio-gateway-cert"
        template = {
          type = "kubernetes.io/tls"
        }
      }
      data = [
        {
          secretKey = "tls.crt"
          remoteRef = {
            key      = var.secrets_manager_secret_path
            property = "tls.crt"
          }
        },
        {
          secretKey = "tls.key"
          remoteRef = {
            key      = var.secrets_manager_secret_path
            property = "tls.key"
          }
        }
      ]
    }
  }

  depends_on = [
    time_sleep.wait_for_istio_namespace
  ]
}