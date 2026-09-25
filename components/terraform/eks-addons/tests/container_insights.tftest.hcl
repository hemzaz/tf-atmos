# Mock-provider tests of enable_container_insights: no AWS or cluster access.

mock_provider "aws" {
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
  override_data {
    target = data.aws_eks_cluster.this
    values = {
      status  = "ACTIVE"
      version = "1.36"
    }
  }
  override_data {
    target = data.aws_eks_addon_version.container_insights
    values = {
      version = "v6.7.0-eksbuild.1"
    }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }
  mock_resource "aws_iam_policy" {
    override_during = plan
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults = {
      arn = "arn:aws:logs:eu-west-2:123456789012:log-group:mock"
    }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "time" {}

variables {
  region                 = "eu-west-2"
  cluster_name           = "production-main"
  host                   = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  oidc_provider_arn      = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  oidc_provider_url      = "https://oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  tags = {
    Environment = "production"
  }
}

run "switch_installs_the_addon_role_and_encrypted_log_groups" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_container_insights             = true
        container_insights_kms_key_arn        = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
        container_insights_log_retention_days = 7
      }
    }
  }

  assert {
    condition     = aws_eks_addon.container_insights["main"].addon_name == "amazon-cloudwatch-observability" && aws_eks_addon.container_insights["main"].cluster_name == "production-main"
    error_message = "The switch must install the amazon-cloudwatch-observability add-on on this cluster."
  }

  assert {
    condition     = aws_eks_addon.container_insights["main"].addon_version == "v6.7.0-eksbuild.1"
    error_message = "Without an override, the add-on runs EKS's default version for the cluster's Kubernetes version."
  }

  assert {
    condition     = aws_eks_addon.container_insights["main"].service_account_role_arn == aws_iam_role.container_insights["main"].arn
    error_message = "The add-on must run with its IRSA role."
  }

  assert {
    condition = jsondecode(aws_iam_role.container_insights["main"].assume_role_policy).Statement[0].Condition.StringEquals == {
      "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
      "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:aud" = "sts.amazonaws.com"
    }
    error_message = "Only amazon-cloudwatch:cloudwatch-agent (agent and Fluent Bit) may assume the role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.container_insights_agent["main"].policy_arn == "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    error_message = "The role must carry CloudWatchAgentServerPolicy."
  }

  assert {
    condition = toset([for g in aws_cloudwatch_log_group.container_insights : g.name]) == toset([
      "/aws/containerinsights/production-main/application",
      "/aws/containerinsights/production-main/dataplane",
      "/aws/containerinsights/production-main/host",
      "/aws/containerinsights/production-main/performance",
    ])
    error_message = "The four Container Insights log groups of this cluster must be created."
  }

  assert {
    condition = alltrue([
      for g in aws_cloudwatch_log_group.container_insights :
      g.kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555" && g.retention_in_days == 7
    ])
    error_message = "Every log group must be encrypted with the given key and keep the given retention."
  }

  assert {
    condition = alltrue([
      for r in jsondecode(aws_iam_policy.container_insights_logs["main"].policy).Statement[0].Resource :
      startswith(r, "arn:aws:logs:eu-west-2:123456789012:log-group:mock")
    ]) && length(jsondecode(aws_iam_policy.container_insights_logs["main"].policy).Statement[0].Resource) == 8
    error_message = "Log writes must be scoped to the four log groups (and their streams), nothing else."
  }

  assert {
    condition = (
      can(jsondecode(aws_eks_addon.container_insights["main"].configuration_values).agent.resources.limits.memory) &&
      can(jsondecode(aws_eks_addon.container_insights["main"].configuration_values).containerLogs.fluentBit.resources.requests.cpu)
    )
    error_message = "The agent and Fluent Bit must have requests and limits."
  }

  assert {
    condition     = aws_iam_role.container_insights["main"].name == "production-main-container-insights-role"
    error_message = "The role name carries the Environment once."
  }
}

run "addon_version_override" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_container_insights        = true
        container_insights_kms_key_arn   = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
        container_insights_addon_version = "v6.6.0-eksbuild.2"
      }
    }
  }

  assert {
    condition     = aws_eks_addon.container_insights["main"].addon_version == "v6.6.0-eksbuild.2"
    error_message = "container_insights_addon_version must pin the add-on."
  }
}

run "off_by_default" {
  command = plan

  variables {
    clusters = {
      main = {}
    }
  }

  assert {
    condition     = length(aws_eks_addon.container_insights) == 0 && length(aws_cloudwatch_log_group.container_insights) == 0 && length(aws_iam_role.container_insights) == 0
    error_message = "Nothing may be created with the switch off."
  }
}

run "needs_a_kms_key" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_container_insights = true
      }
    }
  }

  expect_failures = [var.clusters]
}

run "retention_must_be_a_cloudwatch_value" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_container_insights             = true
        container_insights_kms_key_arn        = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
        container_insights_log_retention_days = 10
      }
    }
  }

  expect_failures = [var.clusters]
}
