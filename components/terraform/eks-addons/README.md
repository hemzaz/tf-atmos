# eks-addons

Installs the cluster add-ons of one EKS cluster: the `enable_*` add-ons
(`addons.tf`), plus any AWS EKS managed addons (`aws_eks_addon`), Helm
releases and raw Kubernetes manifests listed under `var.clusters`. Waits for
the cluster to reach `ACTIVE` and for addons/Helm releases to settle via
`time_sleep` before proceeding. Can optionally install an Istio gateway chart
with a TLS secret sourced from ACM or from `external-secrets`.

## Add-on switches

Each `clusters.<key>.enable_*` switch installs a pinned Helm chart with
resource requests and limits and, when the add-on calls AWS, an IRSA role. The
role's trust allows only the cluster's OIDC provider, audience
`sts.amazonaws.com`, and the add-on's exact `namespace:serviceaccount`. Its
policy is rendered with `templatefile()` from `policies/<add-on>-policy.json`.

| Switch | Chart (version) | Namespace / service account | IAM policy |
|---|---|---|---|
| `enable_aws_load_balancer_controller` | `aws-load-balancer-controller` (1.13.4, controller v2.13.4) | `alb-controller` / `aws-load-balancer-controller` | The AWS-published v2.13.4 policy, unchanged. Needs `vpc_id`. The default `alb` IngressClass is internal (see below). |
| `enable_cluster_autoscaler` | `cluster-autoscaler` (9.59.0, image v1.36.1) | `kube-system` / `cluster-autoscaler` | Describe calls, `eks:DescribeNodegroup` on this cluster's node groups, and scaling only of groups tagged `k8s.io/cluster-autoscaler/<cluster>=owned`. EKS managed node groups carry that tag. |
| `enable_metrics_server` | `metrics-server` (3.11.0) | `metrics-server` / `metrics-server` | None (no AWS calls). |
| `enable_external_dns` | `external-dns` (1.22.0) | `external-dns` / `external-dns` | Record changes on the `dns_zone_ids` zones only, with `--zone-id-filter` set to the same zones. `policy: sync` (required since chart 1.22), TXT records owned by and prefixed with the cluster name. |
| `enable_cert_manager` | `cert-manager` (v1.21.2) plus the local `charts/cert-manager-issuer` | `cert-manager` / `cert-manager` | `route53:GetChange`, `ListHostedZonesByName`, and record changes on the `dns_zone_ids` zones only. Installs a `letsencrypt` ClusterIssuer (ACME DNS-01) for `cert_manager_letsencrypt_email`, against `cert_manager_acme_server` (Let's Encrypt production by default, staging in dev). |

Chart versions, values and IAM statements follow the Cloud Posse components
`eks/alb-controller`, `eks/metrics-server`, `eks/external-dns` and
`eks/cert-manager`. Cloud Posse has no cluster-autoscaler component, so that
chart and its policy follow the kubernetes/autoscaler AWS documentation. The
autoscaler's minor version must match the cluster's. A precondition checks it
against the live cluster, so a Kubernetes upgrade fails the plan until
`cluster_autoscaler_image_tag` in `addons.tf` is bumped.

`clusters.<key>.addon_chart_values.<add-on>` adds Helm values after the
component's own. Every switch defaults to `false`.

The load balancer controller installs first, in its own release
(`helm_release.aws_load_balancer_controller`). Its chart registers a mutating
webhook with `failurePolicy: Fail` on every Service creation, so a Service
created before the controller is ready is rejected. The other add-ons
(`helm_release.addon`), the `helm_releases` entries, and everything ordered
after them wait for it, as in EKS Blueprints and Cloud Posse's components.
`addon_release_statuses` reports both releases.

### Container Insights (`enable_container_insights`, `container-insights.tf`)

Installs the `amazon-cloudwatch-observability` **EKS add-on**: the CloudWatch
agent (Container Insights metrics) and Fluent Bit (application, host and
dataplane logs), both running as `amazon-cloudwatch:cloudwatch-agent`.

- IRSA role trusted only by that service account, with the AWS-managed
  `CloudWatchAgentServerPolicy` (what the add-on documents) plus
  `policies/container-insights-policy.json`: log-stream writes on this
  cluster's four log groups only.
- The log groups `/aws/containerinsights/<cluster>/{application,dataplane,host,performance}`
  are created up front, encrypted with `container_insights_kms_key_arn`
  (`kms/main`, whose policy admits CloudWatch Logs through
  `allow_cloudwatch_logs`) and kept `container_insights_log_retention_days`.
- Agent and Fluent Bit requests/limits are set in `configuration_values`.
- `container_insights_addon_version` pins the add-on; unset, it is EKS's
  default version for the cluster's Kubernetes version.
- The add-on installs after the load balancer controller, whose webhook must
  admit the Services it creates.

Cloud Posse's `eks/cloudwatch` installs the same software from the
`amazon-cloudwatch-observability` Helm chart and attaches
`CloudWatchAgentServerPolicy` to the node roles. The EKS add-on is used here
because it takes an IRSA role directly (`service_account_role_arn`), so only
the agent's service account, not every pod on the node, holds the policy.

`dns_zone_ids` lists **public** hosted zone IDs only (instances pick them from
the dns component's `zone_ids`, e.g. `.zone_ids.main`). Private zones stay out
of both IAM policies.

### Internet-facing load balancers

The controller's default IngressClass (`alb`) creates **internal** ALBs only:
its IngressClassParams set `scheme: internal`, which an Ingress annotation
cannot override. That keeps the repo rule of no inbound `0.0.0.0/0`. Public
entry points sit behind CloudFront. An internet-facing ALB therefore needs:

1. its own IngressClass and IngressClassParams with
   `scheme: internet-facing` (through `addon_chart_values` or a
   `kubernetes_manifests` entry), and
2. on every Ingress of that class, an explicit inbound restriction:
   `alb.ingress.kubernetes.io/security-groups` naming a security group that
   admits only the CloudFront origin-facing prefix list
   (`com.amazonaws.global.cloudfront.origin-facing`), with
   `alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"`.
   Never use `alb.ingress.kubernetes.io/inbound-cidrs: 0.0.0.0/0`.

### Version follow-ups

- aws-load-balancer-controller v3 (chart 3.x) is out. Moving to it means
  re-vendoring its IAM policy and reviewing the v3 changes, so it is left for
  a separate change.
- metrics-server 0.8/0.9 (chart 3.12+) are newer than Cloud Posse's 3.11.0
  default; bump together with a values review.

External Secrets is not a switch. It is the `external-secrets` component,
which has its own instances in every stack.

## Deployed instances

`eks-addons/main` (cluster `eks/main`) and `eks-addons/data` (cluster
`eks/data`) in all 3 real stacks (dev, staging, prod). Both enable the load
balancer controller, cluster-autoscaler, metrics-server, external-dns,
cert-manager and Container Insights (log retention 7 days in dev and
staging, 90 in prod, on `kms/main`). `main` uses the public `network/main` zone (`main`) and `vpc/main`; `data`
uses the public `network/services` zones (`services`, `data`) and `vpc/services`. Dev
uses the Let's Encrypt staging directory.

They deploy in the `addons` layer of `workflows/deploy-full-stack.yaml`,
after `dns`, because they read the dns instances' `zone_ids`.

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `cluster_name`, `host`, `cluster_ca_certificate`, `oidc_provider_arn`, `oidc_provider_url` (the eks instance's outputs); `clusters` map | `clusters.<key>.enable_*`, `vpc_id`, `dns_zone_ids`, `cert_manager_letsencrypt_email`, `cert_manager_acme_server`, `addon_chart_values`, `enable_container_insights`, `container_insights_kms_key_arn`, `container_insights_log_retention_days`, `container_insights_addon_version`; `istio_enabled`/`domain_name`, `use_external_secrets` | `addon_role_arns`, `addon_release_statuses`, `container_insights_role_arns`, `container_insights_log_group_names`, `addon_arns`, `helm_release_statuses`, `service_account_role_arns` (maps) |

## Dependencies & gotchas

- **Private cluster endpoints.** All three stacks run their clusters with
  `cluster_endpoint_public_access: false` (`eks_public_access: false`). The
  `helm` and `kubernetes` providers talk to the cluster API, so
  `atmos terraform plan|apply eks-addons/*` must run from inside the cluster's
  VPC: from the bastion (`ec2/bastion`), a runner in the VPC, or through a
  tunnel to the endpoint. GitHub-hosted runners cannot reach it. The CI plan
  sweep is unaffected because it never reaches a provider.
- The `kubernetes`/`helm` providers connect to the top-level `cluster_name`,
  `host` and `cluster_ca_certificate`: a single cluster. A `clusters` entry's
  `cluster_name` and OIDC provider default to the top-level ones. An entry that
  turns on an `enable_*` add-on must be that cluster (validated). Instances
  therefore hold one cluster each, as Cloud Posse's components do.
- `enable_external_dns` and `enable_cert_manager` require `dns_zone_ids`.
  `enable_aws_load_balancer_controller` requires `vpc_id`. The load balancer
  controller also needs the VPC's subnets tagged `kubernetes.io/role/elb` or
  `kubernetes.io/role/internal-elb`.
- An `addons` entry with `create_service_account_role` gets an IRSA role that
  is attached to the addon, unless the entry sets `service_account_role_arn`.
- The Istio TLS secret needs either `acm_certificate_crt`/`acm_certificate_key` or
  `use_external_secrets = true` with `secrets_manager_secret_path` set.

## Tests

`tests/addons.tftest.hcl` covers the switches with mock providers and needs no
AWS access. It checks the release and role each switch creates, the trust
scoping, and the policy scoping (zones, autoscaler tag, the published load
balancer controller policy). Run it with
`terraform init -backend=false && terraform test` in this directory.

## Usage

```
atmos terraform plan eks-addons/main -s fnx-dev-testenv-01
```
