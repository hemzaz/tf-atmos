# alb-controller-ingress-group

Provisions the shared ALB behind an in-cluster AWS Load Balancer Controller IngressGroup, modelled
on Cloud Posse's `cloudposse-terraform-components/aws-eks-alb-controller-ingress-group`: a
`kubernetes_ingress_v1` carrying only the group's shared settings (`alb.ingress.kubernetes.io/group.name`,
`scheme`, `listen-ports`, a fixed 404 default backend) so the controller provisions the group's ALB, then
a `data aws_lb` / `data aws_lb_listener` lookup — `depends_on` the Ingress, the same way Cloud Posse's own
component does it — so other components (the intended consumer here: `apigateway`'s `http_routes`) can
reach its listener without their own copy of the ALB's Terraform state. No Terraform resource creates the
ALB itself; the controller does, from the Ingress.

Two differences from the Cloud Posse component, both owner decisions for this repo:

1. It creates and owns its own frontend security group (`aws_security_group.alb` +
   `aws_vpc_security_group_ingress_rule`) instead of letting the controller auto-create one, which
   defaults to internet-facing `0.0.0.0/0` unless restricted. This component's security group admits
   only `var.admit_security_group_ids`, never a CIDR — the repo forbids inbound `0.0.0.0/0`/`::/0` —
   attached via the `alb.ingress.kubernetes.io/security-groups` annotation. Naming that annotation stops
   the controller from also managing the backend (node/pod) security group rules on its own, so
   `alb.ingress.kubernetes.io/manage-backend-security-group-rules` is set `"true"` to keep that part
   automatic: the same pattern `eks-addons/README.md`'s "Internet-facing load balancers" section
   documents for an internet-facing ALB behind CloudFront.
2. No `rule` block or backing Kubernetes `Service`: this component only provisions the shared ALB and
   its default 404 backend. Per-microservice routing Ingresses join the same `group.name` and are out
   of this component's scope.

The scheme stays internal regardless of the explicit annotation here: eks-addons's default `alb`
IngressClass pins `ingressClassParams.spec.scheme = internal`, which an Ingress cannot override
(`eks-addons/addons.tf`, README "Internet-facing load balancers"). The annotation is belt-and-braces,
matching what the controller already enforces.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `cluster_name`, `host`, `cluster_ca_certificate` | The EKS cluster (eks outputs `eks_cluster_id`/`eks_cluster_endpoint`/`eks_cluster_certificate_authority_data`). The kubernetes provider's token comes from `data aws_eks_cluster_auth` against `cluster_name` — no `aws` CLI `exec` plugin (unlike `eks-addons`/`external-secrets`): the CI image that runs `terraform validate`/`terraform test` has no `aws` CLI (see the repo's CI image parity note) |
| `vpc_id` | VPC the frontend security group is created in |
| `group_name` | The IngressGroup name; also the `ingress.k8s.aws/stack` tag `data aws_lb` filters on. Validated: lowercase alphanumeric + hyphens, 1-63 characters (a valid IngressGroup name) |
| `admit_security_group_ids` | Required, non-empty. Security groups admitted on the ALB's listener ports — never a CIDR block. Typically the API Gateway VPC link's security group (`microservices/securitygroup/vpc-link`) |
| `certificate_arn` (null) | Set to add an HTTPS (443) listener alongside HTTP (80); null creates HTTP-only |
| `ssl_policy` | TLS policy for the HTTPS listener; ignored unless `certificate_arn` is set |
| `kubernetes_namespace` (`"default"`) | Namespace the IngressGroup scaffold's Ingress is created in |
| Outputs | `group_name`, `ingress_name`, `security_group_id`, `load_balancer_arn`, `load_balancer_dns_name`, `load_balancer_zone_id`, `http_listener_arn`, `https_listener_arn` (null unless `certificate_arn` is set) |

## Dependencies / gotchas

- **Private cluster endpoints.** Like `eks-addons`/`external-secrets`, the `kubernetes` provider talks
  to the cluster API, so `atmos terraform plan|apply alb-controller-ingress-group/*` must run from
  inside the cluster's VPC (bastion, a runner in the VPC, or a tunnel). GitHub-hosted runners cannot
  reach it; the CI plan sweep is unaffected because it never reaches a provider.
- `data.aws_lb.this` and `data.aws_lb_listener.*` `depends_on` `kubernetes_ingress_v1.this`: their
  values are unknown at `plan` on a first apply (there is no ALB to look up yet), the same as any
  data source depending on a resource that has not applied. This is by design, not a bug — Cloud
  Posse's own component has the identical dependency shape.
- Depends on `microservices/eks` (for `cluster_name`/`host`/`cluster_ca_certificate`) and
  `microservices/eks-addons` (the controller must already be installed with its default IngressClass),
  plus `microservices/vpc` for `vpc_id` and whatever security group(s) it admits.
- The frontend security group replaces on any rule change (`name_prefix` +
  `create_before_destroy`), the same trade-off `alb/main.tf` documents for its own security group.

## Tests

`tests/alb-controller-ingress-group.tftest.hcl` runs against mock `aws`/`kubernetes` providers:
`terraform init -backend=false && terraform test`. Covers the group name and internal scheme
annotations, `manage-backend-security-group-rules`, HTTP-only vs. HTTP+HTTPS listen-ports, that every
ingress rule references a security group and never a CIDR, the `admit_security_group_ids`/`group_name`
validations, that the load balancer/listener lookups are wired up, and `enabled = false`.

## Usage

```
atmos terraform plan microservices/alb-ingress-group -s fnx-dev-testenv-01
```
