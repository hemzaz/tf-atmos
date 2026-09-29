# alb-controller-ingress-group

The shared ALB of an AWS Load Balancer Controller IngressGroup, modelled on Cloud Posse
`aws-eks-alb-controller-ingress-group`: a `kubernetes_ingress_v1` carrying only the group's shared
settings and a 404 default backend, so the controller creates the ALB, then `aws_lb` /
`aws_lb_listener` data lookups other components can use. Unlike Cloud Posse it owns its frontend
security group, which admits only `admit_security_group_ids` (never a CIDR), and it creates no
routing rules.

## Wiring

- Used only by the `microservices-platform` template: `microservices/alb-ingress-group` reads
  `microservices/eks`, `microservices/vpc` and a `microservices/acm` certificate, and admits the
  `microservices/securitygroup/vpc-link` group. `microservices/apigateway`'s `http_routes` use its
  `https_listener_arn`.

## Notes

- The ALB stays internal twice over: `spec.ingress_class_name` points at eks-addons' internal `alb`
  IngressClass, and the Ingress sets `scheme: internal`.
- With `certificate_arn` the ALB listens on HTTPS 443 only; without it, HTTP 80 only.
- Every member Ingress that joins the group must set `alb.ingress.kubernetes.io/listen-ports` to the
  `member_listen_ports_annotation` output. The controller unions `listen-ports`, so a member that
  omits it adds an unreachable HTTP 80 listener and its routes silently 404. Members must omit
  `scheme`, `security-groups` and `ssl-policy`.
- The controller-created ALB does not get the `alb` component's hardening automatically: this
  component sets `drop_invalid_header_fields` through `load-balancer-attributes`; access logs are
  opt-in and need a caller-provided bucket. The controller merges `load-balancer-attributes` across
  the group: a member Ingress may add keys but must not set a different value for one this component
  sets (`routing.http.drop_invalid_header_fields.enabled`, `access_logs.s3.*`), or the group build
  conflicts.
- Install eks-addons' load balancer controller and its default `alb` IngressClass first
  (`microservices/eks-addons` is a dependency of the template instance).
- Listener lookups are unknown at plan on the first apply (no ALB yet), as in Cloud Posse.
- Uses `data.aws_eks_cluster_auth` for the provider token; with private endpoints, plan and apply
  from inside the VPC.
