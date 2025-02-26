locals {
  clusters = {
    for k, v in var.clusters : k => v if lookup(v, "enabled", true)
  }

  # Flatten addons across all clusters
  addons = merge([
    for cluster_key, cluster in local.clusters : {
      for addon_key, addon in lookup(cluster, "addons", {}) :
        "${cluster_key}.${addon_key}" => merge(addon, { cluster_name = cluster_key })
      if lookup(addon, "enabled", true)
    }
  ]...)

  # Flatten Helm releases across all clusters
  helm_releases = merge([
    for cluster_key, cluster in local.clusters : {
      for release_key, release in lookup(cluster, "helm_releases", {}) :
        "${cluster_key}.${release_key}" => merge(release, { cluster_name = cluster_key })
      if lookup(release, "enabled", true)
    }
  ]...)

  # Flatten Kubernetes manifests across all clusters
  kubernetes_manifests = merge([
    for cluster_key, cluster in local.clusters : {
      for manifest_key, manifest in lookup(cluster, "kubernetes_manifests", {}) :
        "${cluster_key}.${manifest_key}" => merge(manifest, { cluster_name = cluster_key })
      if lookup(manifest, "enabled", true)
    }
  ]...)
}

# AWS EKS Addons
resource "aws_eks_addon" "addons" {
  for_each = local.addons

  cluster_name             = each.value.cluster_name
  addon_name               = each.value.name
  addon_version            = lookup(each.value, "version", null)
  resolve_conflicts        = lookup(each.value, "resolve_conflicts", "OVERWRITE")
  service_account_role_arn = lookup(each.value, "service_account_role_arn", null)

  preserve = lookup(each.value, "preserve", true)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}"
    }
  )
}

# Helm Provider Configuration
provider "helm" {
  alias = "default"
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

# Dynamic provider configuration for each cluster
locals {
  helm_providers = {
    for cluster_key, cluster in local.clusters : cluster_key => {
      host                   = lookup(cluster, "host", var.host)
      cluster_ca_certificate = lookup(cluster, "cluster_ca_certificate", var.cluster_ca_certificate)
      cluster_name           = lookup(cluster, "eks_cluster_name", var.cluster_name)
    }
  }
}

# Helm Releases
resource "helm_release" "releases" {
  for_each = local.helm_releases

  provider = helm.default # Will be overridden if cluster-specific provider is used

  name             = lookup(each.value, "release_name", each.key)
  chart            = each.value.chart
  repository       = lookup(each.value, "repository", null)
  version          = lookup(each.value, "chart_version", null)
  namespace        = lookup(each.value, "namespace", "default")
  create_namespace = lookup(each.value, "create_namespace", true)

  values = lookup(each.value, "values", [])

  set {
    name  = "clusterName"
    value = each.value.cluster_name
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

  timeout    = lookup(each.value, "timeout", 300)
  atomic     = lookup(each.value, "atomic", true)
  wait       = lookup(each.value, "wait", true)
  depends_on = [aws_eks_addon.addons]
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  alias = "default"
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

  provider = kubernetes.default # Will be overridden if cluster-specific provider is used

  manifest = each.value.manifest

  field_manager {
    name            = lookup(each.value, "field_manager_name", "${var.tags["Environment"]}-${each.value.cluster_name}")
    force_conflicts = lookup(each.value, "force_conflicts", true)
  }

  depends_on = [
    aws_eks_addon.addons,
    helm_release.releases
  ]
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
      role_name = aws_iam_role.service_account[k].name
      policy_arn = v.arn
    }
  }

  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}
