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

Because the controller — not this component — creates the ALB, it does not inherit the hardening the
repo's own `alb` component always applies (`stacks/catalog/alb/defaults.yaml`:
`drop_invalid_header_fields = true`, `access_logs_enabled = true`) unless this component sets it itself
via `alb.ingress.kubernetes.io/load-balancer-attributes`. It always sets
`routing.http.drop_invalid_header_fields.enabled=true`; access logs are opt-in
(`enable_access_logs`/`access_logs_s3_bucket`/`access_logs_s3_prefix` below) because this component has
no bucket of its own to point at — see "Inputs / Outputs".

The scheme stays internal because of two independent enforcements: `spec.ingress_class_name` (below,
`var.ingress_class_name`, default `"alb"`) names eks-addons's default IngressClass explicitly, whose
`ingressClassParams.spec.scheme = internal` an Ingress cannot override (`eks-addons/addons.tf`, README
"Internet-facing load balancers") -- unlike the deprecated `kubernetes.io/ingress.class` annotation,
which the controller still matches on but whose `ingressClassParams` lookup only resolves through
`spec.ingress_class_name`; and the explicit `alb.ingress.kubernetes.io/scheme = internal` annotation
here, belt-and-braces in case `ingressClassParams` is ever loosened.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `cluster_name`, `host`, `cluster_ca_certificate` | The EKS cluster (eks outputs `eks_cluster_id`/`eks_cluster_endpoint`/`eks_cluster_certificate_authority_data`). The kubernetes provider's token comes from `data aws_eks_cluster_auth` against `cluster_name` — no `aws` CLI `exec` plugin (unlike `eks-addons`/`external-secrets`): the CI image that runs `terraform validate`/`terraform test` has no `aws` CLI (see the repo's CI image parity note) |
| `vpc_id` | VPC the frontend security group is created in |
| `group_name` | The IngressGroup name; also the `ingress.k8s.aws/stack` tag `data aws_lb` filters on. Validated: lowercase alphanumeric + hyphens, 1-63 characters (a valid IngressGroup name) |
| `admit_security_group_ids` | Required, non-empty. Security groups admitted on the ALB's listener ports — never a CIDR block. Typically the API Gateway VPC link's security group (`microservices/securitygroup/vpc-link`) |
| `ingress_class_name` (`"alb"`) | The IngressClass this Ingress's `spec.ingress_class_name` references — eks-addons's default IngressClass name |
| `certificate_arn` (null) | ACM certificate ARN; when set the ALB listens on HTTPS (443) only, *replacing* HTTP (80) — never both, so no plaintext listener stays reachable once TLS is on. Null (default) creates an HTTP-only (80) ALB. `microservices-platform` sets this from a `microservices/acm` instance, so `apigateway`'s `http_routes` hop to this ALB is TLS end to end (see `apigateway/README.md`) |
| `ssl_policy` | TLS policy for the HTTPS listener; ignored unless `certificate_arn` is set |
| `enable_access_logs` (`false`) | Enable ALB access logs via `alb.ingress.kubernetes.io/load-balancer-attributes`'s `access_logs.s3.*` keys. Off by default: unlike the `alb` component, this component does not own or create the ALB (the controller does), so it has no bucket of its own to point at — the caller must provide one |
| `access_logs_s3_bucket` | S3 bucket access logs are delivered to. Required (validated) when `enable_access_logs` is true; the bucket's policy must already allow `elasticloadbalancing`'s log delivery service to write to it (see the `alb` component's own access-logs bucket policy for the required shape) |
| `access_logs_s3_prefix` (`""`) | Key prefix for delivered access log objects; ignored unless `enable_access_logs` is true |
| `kubernetes_namespace` (`"alb-ingress-group"`) | Namespace the IngressGroup scaffold's Ingress is created in. Never `"default"` (validated, `CKV_K8S_21`) |
| `create_namespace` (`true`) | Whether this component creates `kubernetes_namespace`; `false` when it already exists |
| Outputs | `group_name`, `ingress_name`, `security_group_id`, `load_balancer_arn`, `load_balancer_dns_name`, `load_balancer_zone_id`, `http_listener_arn`, `https_listener_arn` (null unless `certificate_arn` is set), `member_listen_ports_annotation` (the exact `alb.ingress.kubernetes.io/listen-ports` value a member Ingress joining `group_name` must set — see the gotcha below) |

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
- The frontend security group itself (`aws_security_group.alb`) only replaces when its `name_prefix`,
  `description` or `vpc_id` changes; `create_before_destroy` covers that case, the same trade-off
  `alb/main.tf` documents for its own security group. Changing `admit_security_group_ids` or the ports
  in `listen_ports` only adds or removes the separate `aws_vpc_security_group_ingress_rule` resources
  in place — it does not replace the group. `listen_ports` itself switches wholesale between
  `[{ HTTP = 80 }]` and `[{ HTTPS = 443 }]` on `certificate_arn`, so setting or clearing it also adds
  or removes that port's ingress rule and the corresponding `data aws_lb_listener` lookup.
- **Group-wide annotations fall into two categories, and mixing them up breaks routing.** `scheme`,
  `security-groups` and `ssl-policy` are exclusive LoadBalancer-level settings: the controller requires
  every Ingress in the group to either omit them or set the exact same value, and rejects the group on
  a conflict. `listen-ports`, `certificate-arn` and `tags` are **merged (unioned)** across the group
  instead — the controller does not require them to match, it combines them. This matters because this
  component makes the group HTTPS-only once `certificate_arn` is set (`listen_ports` above switches
  wholesale to `[{"HTTPS":443}]`, never `[{"HTTP":80}]`): a member Ingress that joins `group.name` and
  omits `listen-ports` still defaults to `[{"HTTP":80}]` (the AWS Load Balancer Controller's own
  default), and because the annotation is merged rather than validated, the controller adds that HTTP:80
  listener to the shared ALB alongside HTTPS:443 rather than rejecting the group — the member's rules
  land on the new plaintext :80 listener, which `apigateway`'s route (wired to `https_listener_arn`,
  443) never reaches, so every request through that member's rules 404s. The frontend security group
  here does not admit :80 either, so that listener also exists but is unreachable from outside the
  cluster — silent breakage, not a hard failure. **Every member Ingress must therefore set**
  `alb.ingress.kubernetes.io/listen-ports` **explicitly to this component's `member_listen_ports_annotation`
  output** (`'[{"HTTPS":443}]'` when `certificate_arn` is set, `'[{"HTTP":80}]'` otherwise) rather than
  omitting it or hand-copying the value. `certificate-arn` and `tags` are safe to omit on member
  Ingresses (the union already includes this component's values); `scheme`/`security-groups`/`ssl-policy`
  must be omitted entirely on members — setting a different value here conflicts and the exact same
  value is redundant, since those are exclusive to the group-owning Ingress. `load-balancer-attributes`
  (below) is a StringMap annotation the controller merges the same way as `listen-ports`/`certificate-arn`/
  `tags`: member Ingresses may add their own `key=value` pairs, but must not set a different value for a
  key this component already sets (`routing.http.drop_invalid_header_fields.enabled`, and
  `access_logs.s3.*` when `enable_access_logs` is set) or the group build conflicts.
- **Hardening the controller-created ALB does not inherit by default.** Unlike `alb/main.tf`, no
  Terraform resource here sets `aws_lb`'s `drop_invalid_header_fields` or `access_logs` — the controller
  creates the ALB from the Ingress, so this component reaches the same settings only via
  `alb.ingress.kubernetes.io/load-balancer-attributes`. It always sets
  `routing.http.drop_invalid_header_fields.enabled=true` (matching `stacks/catalog/alb/defaults.yaml`'s
  `drop_invalid_header_fields = true`); access logs are opt-in via `enable_access_logs` +
  `access_logs_s3_bucket` (validated: required together) + `access_logs_s3_prefix`, appended to the same
  comma-separated annotation value as `access_logs.s3.enabled=true,access_logs.s3.bucket=...,access_logs.s3.prefix=...`
  — off by default because, unlike `alb`, this component does not create a bucket of its own.

## Tests

`tests/alb-controller-ingress-group.tftest.hcl` runs against mock `aws`/`kubernetes` providers:
`terraform init -backend=false && terraform test`. Covers the group name and internal scheme
annotations, `manage-backend-security-group-rules`, `spec.ingress_class_name` (validated: a valid
DNS-1123 label, and the absence of the deprecated `kubernetes.io/ingress.class` annotation), the
non-default namespace (created by default, skipped with `create_namespace = false`, rejected when
set to `"default"`), HTTP-only vs. HTTPS-only `listen-ports` (never both -- `certificate_arn` set
means port 80 is never admitted and the HTTP listener is never looked up), that
`member_listen_ports_annotation` matches the Ingress's own `listen-ports` annotation in both the
HTTP-only and HTTPS-only cases, that every ingress rule references a security group and never a
CIDR, the `admit_security_group_ids`/`group_name` validations, that the load balancer/listener
lookups are wired up, `enabled = false`, that `load-balancer-attributes` always carries
`routing.http.drop_invalid_header_fields.enabled=true` (with `enable_access_logs` left at its
default `false`, so `access_logs.s3.*` keys are never present), that they do appear -- and only
then -- once `enable_access_logs = true` with `access_logs_s3_bucket` set, and that
`access_logs_s3_bucket` is required when `enable_access_logs` is true.

## Usage

```
atmos terraform plan microservices/alb-ingress-group -s fnx-dev-testenv-01
```
