# eks-addons

The add-ons of one EKS cluster: `enable_*` switches that install pinned Helm charts with resource
limits and per-add-on IRSA roles (AWS Load Balancer Controller, cluster-autoscaler, metrics-server,
external-dns, cert-manager with a Let's Encrypt DNS-01 ClusterIssuer), the
`amazon-cloudwatch-observability` EKS add-on for Container Insights, and any managed addons, Helm
releases and raw manifests listed under `clusters`. Charts, values and IAM statements follow the
Cloud Posse `eks/*` components (cluster-autoscaler follows the upstream AWS docs).

## Wiring

- Instances: `eks-addons/main` and `eks-addons/data` in the three AWS stacks, all switches on;
  `eks-addons/main` also in `fnx-ue2-prod` and `fnx-ew1-prod` (`fnx-ue1-prod`'s and
  `fnx-ew1-prod`'s inherit `eks-addons/prod`, `stacks/catalog/eks-addons/prod.yaml`). Container
  Insights writes to CloudWatch in the stack's own region.
- `main` reads `eks/main` (endpoint, CA, OIDC), `vpc/main .vpc_id`, `network/main .zone_ids.main`
  and `kms/main .key_arn`; `data` reads the same from `eks/data`, `vpc/services` and
  `network/services` (`services` and `data` zones).
- Deploys in the `addons` layer, after `dns`.

## Notes

- The clusters' endpoints are private, so the `helm`/`kubernetes` providers must run from inside
  the VPC; CI/CD/drift run it on the stack's in-VPC runners (`settings.github.runner: in-vpc`,
  see [In-cluster components](../../../docs/OPERATIONS.md#in-cluster-components)).
- One cluster per instance: the providers connect to the top-level `cluster_name`/`host`.
- The load balancer controller installs first (its webhook rejects Services created before it is
  ready); core managed addons install before it, everything else after.
- `dns_zone_ids` takes public zones only. `enable_external_dns` and `enable_cert_manager` need it;
  the load balancer controller needs `vpc_id` and subnets tagged `kubernetes.io/role/(internal-)elb`.
- A precondition fails the plan when the cluster-autoscaler image minor differs from the cluster's
  Kubernetes version; bump `cluster_autoscaler_image_tag` in `addons.tf` with each upgrade.
- `vpc-cni` belongs to the `eks` component (`vpc_cni_addon`, with its IRSA role; the node role has
  no CNI policy), and `clusters` rejects it in `addons`. External Secrets is the
  `external-secrets` component.

## Internet-facing load balancers

The default `alb` IngressClass creates internal ALBs only (`scheme: internal` in its
IngressClassParams, which an Ingress annotation cannot override). An internet-facing ALB needs its
own IngressClass with `scheme: internet-facing`, and every Ingress of that class must set
`alb.ingress.kubernetes.io/security-groups` to a group admitting only the CloudFront origin-facing
prefix list, with `manage-backend-security-group-rules: "true"`. Never use
`inbound-cidrs: 0.0.0.0/0`.
