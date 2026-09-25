# Mock-provider tests of the enable_* add-on switches: no AWS or cluster
# access. Run from the component directory with
# `terraform init -backend=false && terraform test`.

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
      status   = "ACTIVE"
      version  = "1.36"
      endpoint = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
    }
  }
  # Role ARNs are known at plan, so values that carry them can be asserted.
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
}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "time" {}

variables {
  region                 = "eu-west-2"
  cluster_name           = "testenv-01-main"
  host                   = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  oidc_provider_arn      = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  oidc_provider_url      = "https://oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF"
  istio_enabled          = false
  tags = {
    Environment = "testenv-01"
  }
}

run "no_switch_installs_nothing" {
  command = plan

  variables {
    clusters = {
      main = {}
    }
  }

  assert {
    condition     = length(helm_release.aws_load_balancer_controller) == 0 && length(helm_release.addon) == 0 && length(aws_iam_role.addon) == 0 && length(helm_release.cert_manager_issuer) == 0
    error_message = "With every enable_* off, no add-on release or role may be planned."
  }
}

run "each_switch_installs_its_release_and_role" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_aws_load_balancer_controller = true
        enable_cluster_autoscaler           = true
        enable_metrics_server               = true
        enable_external_dns                 = true
        enable_cert_manager                 = true
        vpc_id                              = "vpc-0123456789abcdef0"
        dns_zone_ids                        = ["Z0123456789ABCDEFGHIJ", "Z9876543210ZYXWVUTSRQ"]
        cert_manager_letsencrypt_email      = "ops@example.com"
      }
    }
  }

  assert {
    condition = toset(keys(merge(helm_release.aws_load_balancer_controller, helm_release.addon))) == toset([
      "main.aws-load-balancer-controller", "main.cluster-autoscaler", "main.metrics-server",
      "main.external-dns", "main.cert-manager",
    ])
    error_message = "Each switch must plan exactly its own Helm release."
  }

  # The load balancer controller installs in its own release, ahead of the
  # charts that create Services (its webhook must admit them).
  assert {
    condition     = keys(helm_release.aws_load_balancer_controller) == ["main.aws-load-balancer-controller"] && !contains(keys(helm_release.addon), "main.aws-load-balancer-controller")
    error_message = "The load balancer controller must be planned in helm_release.aws_load_balancer_controller only."
  }

  # metrics-server calls no AWS API: no role.
  assert {
    condition = toset(keys(aws_iam_role.addon)) == toset([
      "main.aws-load-balancer-controller", "main.cluster-autoscaler", "main.external-dns", "main.cert-manager",
    ])
    error_message = "Every add-on that calls AWS, and only those, must get an IRSA role."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.addon)) == toset(keys(aws_iam_role.addon))
    error_message = "Every add-on role must have its policy attached."
  }

  assert {
    condition     = alltrue([for k, r in merge(helm_release.aws_load_balancer_controller, helm_release.addon) : r.version != null && r.version != ""])
    error_message = "Every chart version must be pinned."
  }

  assert {
    condition = alltrue([
      for k, r in merge(helm_release.aws_load_balancer_controller, helm_release.addon) : can(yamldecode(r.values[0]).resources.requests.cpu) && can(yamldecode(r.values[0]).resources.limits.memory)
    ])
    error_message = "Every release must set resource requests and limits."
  }

  assert {
    condition     = helm_release.addon["main.cluster-autoscaler"].version == "9.59.0" && helm_release.addon["main.cert-manager"].version == "v1.21.2" && helm_release.addon["main.external-dns"].version == "1.22.0"
    error_message = "Chart pins changed unexpectedly."
  }

  # Names carry the Environment once (the cluster name already has it).
  assert {
    condition     = aws_iam_role.addon["main.external-dns"].name == "testenv-01-main-external-dns-role"
    error_message = "The role must be <cluster>-<add-on>-role, with the Environment once."
  }

  assert {
    condition     = length(helm_release.cert_manager_issuer) == 1 && strcontains(helm_release.cert_manager_issuer["main"].values[0], "ops@example.com")
    error_message = "cert-manager must come with its Let's Encrypt issuer, using the configured email."
  }

  assert {
    condition     = yamldecode(helm_release.aws_load_balancer_controller["main.aws-load-balancer-controller"].values[1]).vpcId == "vpc-0123456789abcdef0"
    error_message = "The load balancer controller must be given the VPC."
  }

  # No inbound 0.0.0.0/0: the default IngressClass makes internal ALBs only,
  # pinned in its IngressClassParams so an Ingress cannot override it.
  assert {
    condition = (
      yamldecode(helm_release.aws_load_balancer_controller["main.aws-load-balancer-controller"].values[1]).createIngressClassResource == true &&
      yamldecode(helm_release.aws_load_balancer_controller["main.aws-load-balancer-controller"].values[1]).ingressClassParams.create == true &&
      yamldecode(helm_release.aws_load_balancer_controller["main.aws-load-balancer-controller"].values[1]).ingressClassParams.spec.scheme == "internal"
    )
    error_message = "The default IngressClass must create internal load balancers."
  }

  assert {
    condition     = !strcontains(join("\n", helm_release.aws_load_balancer_controller["main.aws-load-balancer-controller"].values), "internet-facing")
    error_message = "Nothing in the load balancer controller's values may ask for internet-facing."
  }

  assert {
    condition     = yamldecode(helm_release.addon["main.external-dns"].values[1]).txtPrefix == "testenv-01-main-" && yamldecode(helm_release.addon["main.external-dns"].values[1]).policy == "sync"
    error_message = "external-dns must prefix its TXT ownership records with the cluster name and set policy (required from chart 1.22)."
  }

  assert {
    condition     = strcontains(helm_release.cert_manager_issuer["main"].values[0], "https://acme-v02.api.letsencrypt.org/directory")
    error_message = "The issuer must default to the Let's Encrypt production directory."
  }

  assert {
    condition     = yamldecode(helm_release.addon["main.cluster-autoscaler"].values[1]).autoDiscovery.clusterName == "testenv-01-main"
    error_message = "cluster-autoscaler must auto-discover this cluster's groups."
  }
}

run "trust_is_scoped_to_the_oidc_provider_and_service_account" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_aws_load_balancer_controller = true
        enable_external_dns                 = true
        vpc_id                              = "vpc-0123456789abcdef0"
        dns_zone_ids                        = ["Z0123456789ABCDEFGHIJ"]
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.addon["main.external-dns"].assume_role_policy).Statement[0].Condition.StringEquals == {
      "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:sub" = "system:serviceaccount:external-dns:external-dns"
      "oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:aud" = "sts.amazonaws.com"
    }
    error_message = "external-dns must be assumable only by external-dns:external-dns, audience STS."
  }

  assert {
    condition     = jsondecode(aws_iam_role.addon["main.aws-load-balancer-controller"].assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-2.amazonaws.com/id/ABCDEF:sub"] == "system:serviceaccount:alb-controller:aws-load-balancer-controller"
    error_message = "The load balancer controller must be assumable only by its own namespace:serviceaccount."
  }

  assert {
    condition     = jsondecode(aws_iam_role.addon["main.external-dns"].assume_role_policy).Statement[0].Principal.Federated == var.oidc_provider_arn
    error_message = "The trust must federate only this cluster's OIDC provider."
  }

  # The release runs as the role's service account, annotated with the role.
  assert {
    condition     = yamldecode(helm_release.addon["main.external-dns"].values[2]).serviceAccount.name == "external-dns" && helm_release.addon["main.external-dns"].namespace == "external-dns"
    error_message = "The chart's service account must be the one the trust names."
  }

  assert {
    condition     = yamldecode(helm_release.addon["main.external-dns"].values[2]).serviceAccount.annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.addon["main.external-dns"].arn
    error_message = "The service account must be annotated with the add-on's role."
  }
}

run "policies_are_scoped" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_cluster_autoscaler      = true
        enable_external_dns            = true
        enable_cert_manager            = true
        dns_zone_ids                   = ["Z9876543210ZYXWVUTSRQ", "Z0123456789ABCDEFGHIJ"]
        cert_manager_letsencrypt_email = "ops@example.com"
      }
    }
  }

  # external-dns may change records in exactly the stack's zones.
  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.addon["main.external-dns"].policy).Statement : s.Resource if s.Sid == "GrantChangeResourceRecordSets"
      ][0] == [
      "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ",
      "arn:aws:route53:::hostedzone/Z9876543210ZYXWVUTSRQ",
    ]
    error_message = "external-dns record changes must be limited to the dns_zone_ids zones."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.addon["main.external-dns"].policy, "hostedzone/*")
    error_message = "external-dns must not be granted every hosted zone."
  }

  # cert-manager: Route 53 changes only on those zones.
  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.addon["main.cert-manager"].policy).Statement : s.Resource if s.Sid == "GrantChangeResourceRecordSets"
      ][0] == [
      "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ",
      "arn:aws:route53:::hostedzone/Z9876543210ZYXWVUTSRQ",
    ]
    error_message = "cert-manager record changes must be limited to the dns_zone_ids zones."
  }

  assert {
    condition     = !strcontains(aws_iam_policy.addon["main.cert-manager"].policy, "hostedzone/*")
    error_message = "cert-manager must not be granted every hosted zone."
  }

  # cluster-autoscaler may scale only groups tagged as this cluster's.
  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.addon["main.cluster-autoscaler"].policy).Statement : s.Condition.StringEquals if s.Sid == "ScaleThisClustersGroups"
    ][0] == { "aws:ResourceTag/k8s.io/cluster-autoscaler/testenv-01-main" = "owned" }
    error_message = "Scaling must be conditioned on the k8s.io/cluster-autoscaler/<cluster> tag."
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.addon["main.cluster-autoscaler"].policy).Statement : s.Resource if s.Sid == "DescribeThisClustersNodegroups"
    ][0] == "arn:aws:eks:eu-west-2:123456789012:nodegroup/testenv-01-main/*/*"
    error_message = "eks:DescribeNodegroup must be limited to this cluster's node groups."
  }

  assert {
    condition     = yamldecode(helm_release.addon["main.external-dns"].values[1]).extraArgs == ["--zone-id-filter=Z0123456789ABCDEFGHIJ", "--zone-id-filter=Z9876543210ZYXWVUTSRQ"]
    error_message = "external-dns must only watch the zones its policy allows."
  }
}

run "load_balancer_controller_uses_the_published_policy" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_aws_load_balancer_controller = true
        vpc_id                              = "vpc-0123456789abcdef0"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_policy.addon["main.aws-load-balancer-controller"].policy) == jsondecode(file("${path.module}/policies/aws-load-balancer-controller-policy.json"))
    error_message = "The load balancer controller policy must be the AWS-published policy, unchanged."
  }
}

run "dns_addons_need_zones" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_external_dns = true
      }
    }
  }

  expect_failures = [var.clusters]
}

run "load_balancer_controller_needs_the_vpc" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_aws_load_balancer_controller = true
      }
    }
  }

  expect_failures = [var.clusters]
}

run "addons_only_install_into_the_provider_cluster" {
  command = plan

  variables {
    clusters = {
      other = {
        cluster_name          = "testenv-01-data"
        enable_metrics_server = true
      }
    }
  }

  expect_failures = [var.clusters]
}

run "hosted_zone_path_is_rejected" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_external_dns = true
        dns_zone_ids        = ["/hostedzone/Z0123456789ABCDEFGHIJ"]
      }
    }
  }

  expect_failures = [var.clusters]
}

run "autoscaler_minor_must_match_the_cluster" {
  command = plan

  override_data {
    target = data.aws_eks_cluster.this
    values = {
      status  = "ACTIVE"
      version = "1.37"
    }
  }

  variables {
    clusters = {
      main = {
        enable_cluster_autoscaler = true
      }
    }
  }

  expect_failures = [helm_release.addon]
}

# helm_releases entries still install, next to the switched-on add-ons, and
# the settle timer reads only attributes helm_release exports.
run "helm_releases_still_install" {
  command = apply

  variables {
    clusters = {
      main = {
        enable_metrics_server = true
        helm_releases = {
          reloader = {
            chart         = "reloader"
            repository    = "https://stakater.github.io/stakater-charts"
            chart_version = "2.1.3"
            namespace     = "reloader"
          }
        }
      }
    }
  }

  assert {
    condition     = helm_release.releases["main.reloader"].version == "2.1.3" && length(helm_release.addon) == 1
    error_message = "helm_releases and the add-on switches must both install."
  }
}

# An aws_eks_addon's create_service_account_role now attaches its role.
run "eks_addon_role_is_attached" {
  command = plan

  variables {
    clusters = {
      main = {
        addons = {
          ebs = {
            name                        = "aws-ebs-csi-driver"
            create_service_account_role = true
            service_account_name        = "ebs-csi-controller-sa"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_eks_addon.core["main.ebs"].service_account_role_arn == aws_iam_role.service_account["main.ebs"].arn
    error_message = "The addon must run with the IRSA role created for it."
  }

  assert {
    condition     = aws_eks_addon.core["main.ebs"].cluster_name == "testenv-01-main"
    error_message = "The addon must target the real cluster name, not the clusters key."
  }

  assert {
    condition     = aws_iam_role.service_account["main.ebs"].name == "testenv-01-main-aws-ebs-csi-driver-sa-role"
    error_message = "The addon role name carries the Environment once."
  }
}

# Core managed add-ons (CNI, DNS, ...) install before the load balancer
# controller; any other managed add-on after it (its webhook admits Services).
run "managed_addons_split_around_the_load_balancer_controller" {
  command = plan

  variables {
    clusters = {
      main = {
        addons = {
          vpc-cni = { name = "vpc-cni" }
          coredns = { name = "coredns" }
          adot    = { name = "adot" }
        }
      }
    }
  }

  assert {
    condition     = toset(keys(aws_eks_addon.core)) == toset(["main.vpc-cni", "main.coredns"]) && keys(aws_eks_addon.addons) == ["main.adot"]
    error_message = "vpc-cni and coredns must be core add-ons; adot must install after the load balancer controller."
  }

  assert {
    condition     = toset(keys(output.addon_arns)) == toset(["main.vpc-cni", "main.coredns", "main.adot"])
    error_message = "addon_arns must report both groups."
  }
}

run "acme_staging_directory_for_non_production" {
  command = plan

  variables {
    clusters = {
      main = {
        enable_cert_manager            = true
        dns_zone_ids                   = ["Z0123456789ABCDEFGHIJ"]
        cert_manager_letsencrypt_email = "ops@example.com"
        cert_manager_acme_server       = "https://acme-staging-v02.api.letsencrypt.org/directory"
      }
    }
  }

  assert {
    condition     = strcontains(helm_release.cert_manager_issuer["main"].values[0], "https://acme-staging-v02.api.letsencrypt.org/directory")
    error_message = "cert_manager_acme_server must reach the issuer."
  }
}

run "other_acme_directory_is_rejected" {
  command = plan

  variables {
    clusters = {
      main = {
        cert_manager_acme_server = "https://acme.example.com/directory"
      }
    }
  }

  expect_failures = [var.clusters]
}
