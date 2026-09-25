# ============================================================================
# Container Insights (clusters.<key>.enable_container_insights)
# ============================================================================
# The amazon-cloudwatch-observability EKS add-on: the CloudWatch agent
# (Container Insights metrics) and Fluent Bit (container, host and dataplane
# logs), both running as amazon-cloudwatch:cloudwatch-agent.
#
# Cloud Posse's eks/cloudwatch installs the same software from the
# amazon-cloudwatch-observability Helm chart and grants
# CloudWatchAgentServerPolicy to the node roles. Here the add-on gets the
# policy through IRSA instead (AWS's documented option for the add-on:
# service_account_role_arn), so only its own service account holds it, plus
# a policy scoped to this cluster's log groups. The log groups are created up
# front, KMS-encrypted and with a retention, instead of being auto-created
# unencrypted by the agents.
# ============================================================================

locals {
  container_insights_namespace       = "amazon-cloudwatch"
  container_insights_service_account = "cloudwatch-agent"

  container_insights = {
    for ck, c in local.clusters : ck => c if c.enable_container_insights
  }

  # The four groups the add-on writes to: performance (agent metrics as
  # EMF) and application, host, dataplane (Fluent Bit).
  container_insights_log_groups = merge([
    for ck, c in local.container_insights : {
      for t in ["application", "dataplane", "host", "performance"] : "${ck}.${t}" => {
        cluster_key = ck
        name        = "/aws/containerinsights/${c.cluster_name}/${t}"
      }
    }
  ]...)
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = local.container_insights_log_groups

  name              = each.value.name
  retention_in_days = local.clusters[each.value.cluster_key].container_insights_log_retention_days
  kms_key_id        = local.clusters[each.value.cluster_key].container_insights_kms_key_arn

  tags = merge(var.tags, local.clusters[each.value.cluster_key].tags, { Name = each.value.name })
}

resource "aws_iam_role" "container_insights" {
  for_each = local.container_insights

  name = "${local.cluster_name_prefixes[each.key]}-container-insights-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = each.value.oidc_provider_arn }
        Condition = {
          StringEquals = {
            "${local.oidc_issuer_hosts[each.key]}:sub" = "system:serviceaccount:${local.container_insights_namespace}:${local.container_insights_service_account}"
            "${local.oidc_issuer_hosts[each.key]}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, each.value.tags, { Name = "${local.cluster_name_prefixes[each.key]}-container-insights-role" })

  lifecycle {
    precondition {
      condition     = length("${local.cluster_name_prefixes[each.key]}-container-insights-role") <= 64
      error_message = "IAM role name ${local.cluster_name_prefixes[each.key]}-container-insights-role is longer than 64 characters; shorten the cluster name."
    }
  }
}

# The AWS-managed policy the add-on documents (metrics, EC2/EKS describe, logs).
resource "aws_iam_role_policy_attachment" "container_insights_agent" {
  for_each = local.container_insights

  role       = aws_iam_role.container_insights[each.key].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_policy" "container_insights_logs" {
  for_each = local.container_insights

  name        = "${local.cluster_name_prefixes[each.key]}-container-insights-logs-policy"
  description = "Container Insights log writes to ${each.value.cluster_name}'s /aws/containerinsights log groups"
  policy = templatefile("${path.module}/policies/container-insights-policy.json", {
    log_group_arns = flatten([
      for k, g in local.container_insights_log_groups : [
        aws_cloudwatch_log_group.container_insights[k].arn,
        "${aws_cloudwatch_log_group.container_insights[k].arn}:log-stream:*",
      ] if g.cluster_key == each.key
    ])
  })

  tags = merge(var.tags, each.value.tags, { Name = "${local.cluster_name_prefixes[each.key]}-container-insights-logs-policy" })
}

resource "aws_iam_role_policy_attachment" "container_insights_logs" {
  for_each = local.container_insights

  role       = aws_iam_role.container_insights[each.key].name
  policy_arn = aws_iam_policy.container_insights_logs[each.key].arn
}

data "aws_eks_addon_version" "container_insights" {
  for_each = { for ck, c in local.container_insights : ck => c if c.container_insights_addon_version == null }

  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = data.aws_eks_cluster.this[each.key].version
  most_recent        = false
}

resource "aws_eks_addon" "container_insights" {
  for_each = local.container_insights

  cluster_name  = each.value.cluster_name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = coalesce(each.value.container_insights_addon_version, try(data.aws_eks_addon_version.container_insights[each.key].version, null))

  service_account_role_arn    = aws_iam_role.container_insights[each.key].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Requests and limits for both workloads (the chart's own defaults, set
  # explicitly).
  configuration_values = jsonencode({
    agent = {
      resources = { requests = { cpu = "250m", memory = "128Mi" }, limits = { cpu = "500m", memory = "512Mi" } }
    }
    containerLogs = {
      enabled = true
      fluentBit = {
        resources = { requests = { cpu = "50m", memory = "25Mi" }, limits = { cpu = "500m", memory = "250Mi" } }
      }
    }
  })

  tags = merge(var.tags, each.value.tags, { Name = "${local.cluster_name_prefixes[each.key]}-container-insights" })

  # The add-on creates Services, which the load balancer controller's webhook
  # (failurePolicy Fail) must admit: install it after that release (addons.tf).
  depends_on = [
    time_sleep.wait_for_cluster,
    helm_release.aws_load_balancer_controller,
    aws_cloudwatch_log_group.container_insights,
    aws_iam_role_policy_attachment.container_insights_agent,
    aws_iam_role_policy_attachment.container_insights_logs,
  ]
}
