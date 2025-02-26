# components/terraform/eks-addons/main.tf
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

# Get cluster info to validate it's accessible before proceeding
data "aws_eks_cluster" "this" {
  for_each = local.clusters
  name     = each.key
}

# Wait for EKS cluster to be fully ready
resource "time_sleep" "wait_for_cluster" {
  for_each = local.clusters

  depends_on = [
    data.aws_eks_cluster.this
  ]

  # Increased wait time to ensure cluster is fully ready
  create_duration = "120s"
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

# AWS EKS Addons
resource "aws_eks_addon" "addons" {
  for_each = local.addons

  cluster_name             = each.value.cluster_name
  addon_name               = each.value.name
  addon_version            = lookup(each.value, "version", null)
  resolve_conflicts        = lookup(each.value, "resolve_conflicts", "OVERWRITE")
  service_account_role_arn = lookup(each.value, "service_account_role_arn",
                               lookup(each.value, "create_service_account_role", false) ?
                               aws_iam_role.service_account["${each.value.cluster_name}.${each.value.name}"].arn : null)

  preserve = lookup(each.value, "preserve", true)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.value.cluster_name}-${each.value.name}"
    }
  )

  # Add dependency on wait_for_cluster
  depends_on = [
    time_sleep.wait_for_cluster,
    aws_iam_role_policy_attachment.service_account
  ]
}

# Wait for addons to be ready before proceeding with helm releases
resource "time_sleep" "wait_for_addons" {
  count = length(local.addons) > 0 ? 1 : 0

  depends_on = [
    aws_eks_addon.addons,
    aws_iam_role_policy_attachment.service_account
  ]

  # Allow more time for addons to initialize
  create_duration = "30s"
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

  # Wait for addons and service accounts to be created
  depends_on = [
    time_sleep.wait_for_addons,
    aws_iam_role_policy_attachment.service_account,
    time_sleep.wait_for_cluster
  ]
}

# Wait for helm releases to be ready before proceeding with kubernetes manifests
resource "time_sleep" "wait_for_helm_releases" {
  count = length(local.helm_releases) > 0 ? 1 : 0

  depends_on = [
    helm_release.releases
  ]

  # Allow more time for Helm releases to stabilize
  create_duration = "45s"
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