# ============================================================================
# Add-ons behind the clusters.<key>.enable_* switches
# ============================================================================
# Each switch installs one pinned Helm chart and, where the add-on calls AWS,
# an IRSA role whose trust is limited to the cluster's OIDC provider and the
# chart's exact namespace:serviceaccount, with a least-privilege policy
# rendered from policies/<add-on>-policy.json.
#
# Cloud Posse ships these as separate components (eks/alb-controller,
# eks/metrics-server, eks/external-dns, eks/cert-manager), each a helm release
# plus IRSA through cloudposse/helm-release/aws. Chart versions, values,
# resources and IAM statements follow those components. Cloud Posse has no
# cluster-autoscaler component (it uses Karpenter); that chart and policy
# follow the kubernetes/autoscaler AWS documentation.
#
# The kubernetes/helm providers connect to var.cluster_name only, so a
# clusters entry that enables a switch must be that cluster (validated on
# var.clusters).
# ============================================================================

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # Chart pins. Update a version together with its IAM policy (the load
  # balancer controller's policy is published per release).
  addon_charts = {
    aws-load-balancer-controller = {
      repository = "https://aws.github.io/eks-charts"
      chart      = "aws-load-balancer-controller"
      version    = "1.13.4" # controller v2.13.4, the policy in policies/
      namespace  = "alb-controller"
      policy     = "aws-load-balancer-controller-policy.json"
      resources  = { requests = { cpu = "100m", memory = "128Mi" }, limits = { cpu = "200m", memory = "256Mi" } }
    }
    cluster-autoscaler = {
      repository = "https://kubernetes.github.io/autoscaler"
      chart      = "cluster-autoscaler"
      version    = "9.59.0"
      namespace  = "kube-system"
      policy     = "cluster-autoscaler-policy.json"
      resources  = { requests = { cpu = "100m", memory = "300Mi" }, limits = { cpu = "200m", memory = "600Mi" } }
    }
    metrics-server = {
      repository = "https://kubernetes-sigs.github.io/metrics-server/"
      chart      = "metrics-server"
      version    = "3.11.0"
      namespace  = "metrics-server"
      policy     = null # calls no AWS API, so no IRSA role
      resources  = { requests = { cpu = "20m", memory = "60Mi" }, limits = { cpu = "100m", memory = "300Mi" } }
    }
    external-dns = {
      repository = "https://kubernetes-sigs.github.io/external-dns/"
      chart      = "external-dns"
      version    = "1.18.0"
      namespace  = "external-dns"
      policy     = "external-dns-policy.json"
      resources  = { requests = { cpu = "100m", memory = "128Mi" }, limits = { cpu = "200m", memory = "256Mi" } }
    }
    cert-manager = {
      repository = "https://charts.jetstack.io"
      chart      = "cert-manager"
      version    = "v1.21.1"
      namespace  = "cert-manager"
      policy     = "cert-manager-policy.json"
      resources  = { requests = { cpu = "100m", memory = "128Mi" }, limits = { cpu = "200m", memory = "256Mi" } }
    }
  }

  # The chart ships cluster-autoscaler v1.35; the autoscaler's minor must
  # match the cluster's (checked against the live cluster before install).
  cluster_autoscaler_image_tag = "v1.36.1"

  # One entry per (cluster, switched-on add-on). The service account is named
  # after the add-on, as Cloud Posse names it after the component.
  addon_releases = merge([
    for ck, c in local.clusters : {
      for name, on in {
        aws-load-balancer-controller = c.enable_aws_load_balancer_controller
        cluster-autoscaler           = c.enable_cluster_autoscaler
        metrics-server               = c.enable_metrics_server
        external-dns                 = c.enable_external_dns
        cert-manager                 = c.enable_cert_manager
        } : "${ck}.${name}" => merge(local.addon_charts[name], {
          cluster_key     = ck
          name            = name
          service_account = name
          role_name       = "${local.cluster_name_prefixes[ck]}-${name}"
      }) if on
    }
  ]...)

  addon_roles = { for k, v in local.addon_releases : k => v if v.policy != null }

  # Every variable a policy template may use; each template reads its own.
  policy_vars = {
    for ck, c in local.clusters : ck => {
      partition        = data.aws_partition.current.partition
      region           = var.region
      account_id       = data.aws_caller_identity.current.account_id
      cluster_name     = c.cluster_name
      hosted_zone_arns = [for id in sort(distinct(values(c.dns_zone_ids))) : "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${id}"]
    }
  }

  service_account_values = {
    for k, v in local.addon_releases : k => {
      create      = true
      name        = v.service_account
      annotations = v.policy == null ? {} : { "eks.amazonaws.com/role-arn" = aws_iam_role.addon[k].arn }
    }
  }

  # Chart-specific values (YAML), from the Cloud Posse component of the same
  # add-on. The shapes differ per chart, hence one YAML document each.
  addon_values = {
    for k, v in local.addon_releases : k => {
      aws-load-balancer-controller = yamlencode({
        clusterName    = local.clusters[v.cluster_key].cluster_name
        region         = var.region
        vpcId          = local.clusters[v.cluster_key].vpc_id
        serviceAccount = local.service_account_values[k]
      })
      cluster-autoscaler = yamlencode({
        cloudProvider = "aws"
        awsRegion     = var.region
        autoDiscovery = { clusterName = local.clusters[v.cluster_key].cluster_name }
        image         = { tag = local.cluster_autoscaler_image_tag }
        rbac          = { create = true, serviceAccount = local.service_account_values[k] }
      })
      metrics-server = yamlencode({
        serviceAccount      = local.service_account_values[k]
        rbac                = { create = true }
        apiService          = { create = true }
        podDisruptionBudget = { enabled = true, maxUnavailable = "75%" }
      })
      external-dns = yamlencode({
        provider       = { name = "aws" }
        policy         = "sync"
        sources        = ["service", "ingress"]
        txtOwnerId     = local.clusters[v.cluster_key].cluster_name
        domainFilters  = local.clusters[v.cluster_key].external_dns_domain_filters
        extraArgs      = [for id in sort(distinct(values(local.clusters[v.cluster_key].dns_zone_ids))) : "--zone-id-filter=${id}"]
        serviceAccount = local.service_account_values[k]
      })
      cert-manager = yamlencode({
        crds            = { enabled = true, keep = true }
        serviceAccount  = local.service_account_values[k]
        securityContext = { fsGroup = 1001, runAsUser = 1001 }
        webhook         = { resources = { requests = { cpu = "50m", memory = "64Mi" }, limits = { cpu = "100m", memory = "128Mi" } } }
        cainjector      = { enabled = true, resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { cpu = "100m", memory = "256Mi" } } }
        startupapicheck = { resources = { requests = { cpu = "10m", memory = "32Mi" }, limits = { cpu = "50m", memory = "64Mi" } } }
      })
    }[v.name]
  }
}

resource "aws_iam_role" "addon" {
  for_each = local.addon_roles

  name = "${each.value.role_name}-role"

  # Only this cluster's OIDC provider, and only the add-on's own service
  # account: sub pins namespace:serviceaccount, aud pins STS.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = local.clusters[each.value.cluster_key].oidc_provider_arn }
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_hosts[each.value.cluster_key]}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
            "${local.oidc_issuer_hosts[each.value.cluster_key]}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, local.clusters[each.value.cluster_key].tags, { Name = "${each.value.role_name}-role" })

  lifecycle {
    precondition {
      condition     = length("${each.value.role_name}-role") <= 64
      error_message = "IAM role name ${each.value.role_name}-role is longer than 64 characters; shorten the cluster name."
    }
  }
}

resource "aws_iam_policy" "addon" {
  for_each = local.addon_roles

  name        = "${each.value.role_name}-policy"
  description = "IRSA policy for ${each.value.name} in ${local.clusters[each.value.cluster_key].cluster_name}"
  policy      = templatefile("${path.module}/policies/${each.value.policy}", local.policy_vars[each.value.cluster_key])

  tags = merge(var.tags, local.clusters[each.value.cluster_key].tags, { Name = "${each.value.role_name}-policy" })
}

resource "aws_iam_role_policy_attachment" "addon" {
  for_each = local.addon_roles

  role       = aws_iam_role.addon[each.key].name
  policy_arn = aws_iam_policy.addon[each.key].arn
}

resource "helm_release" "addon" {
  for_each = local.addon_releases

  name             = each.value.name
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = true

  # Base values, then the stack's clusters.<key>.addon_chart_values.<add-on>.
  values = [
    yamlencode({ fullnameOverride = each.value.name, resources = each.value.resources }),
    local.addon_values[each.key],
    yamlencode(lookup(local.clusters[each.value.cluster_key].addon_chart_values, each.value.name, {})),
  ]

  # wait: the load balancer controller's webhooks and cert-manager's CRDs must
  # be serving before anything that uses them is applied.
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  depends_on = [
    time_sleep.wait_for_cluster,
    aws_iam_role_policy_attachment.addon,
  ]

  lifecycle {
    precondition {
      condition     = each.value.name != "cluster-autoscaler" || startswith(local.cluster_autoscaler_image_tag, "v${data.aws_eks_cluster.this[each.value.cluster_key].version}.")
      error_message = "cluster-autoscaler ${local.cluster_autoscaler_image_tag} does not match the cluster's Kubernetes ${data.aws_eks_cluster.this[each.value.cluster_key].version}; update cluster_autoscaler_image_tag in addons.tf."
    }
  }
}

# Let's Encrypt ClusterIssuer (ACME DNS-01 through Route 53, using the
# cert-manager role above), from a local chart so the first apply does not
# need the cert-manager CRDs at plan time. Cloud Posse installs its issuers
# the same way (cert_manager_issuer, a local chart).
resource "helm_release" "cert_manager_issuer" {
  for_each = { for k, v in local.addon_releases : v.cluster_key => v if v.name == "cert-manager" }

  name      = "cert-manager-issuer"
  chart     = "${path.module}/charts/cert-manager-issuer"
  namespace = each.value.namespace

  values = [
    yamlencode({
      email  = local.clusters[each.key].cert_manager_letsencrypt_email
      region = var.region
    }),
  ]

  wait    = true
  atomic  = true
  timeout = 300

  depends_on = [helm_release.addon]
}
