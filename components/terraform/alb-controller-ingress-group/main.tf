# Shared-ALB IngressGroup scaffold for the in-cluster AWS Load Balancer
# Controller (eks-addons's `enable_aws_load_balancer_controller`), modelled
# on Cloud Posse's aws-eks-alb-controller-ingress-group
# (cloudposse-terraform-components/aws-eks-alb-controller-ingress-group): a
# kubernetes_ingress_v1 that carries only the IngressGroup's shared settings
# (group name, scheme, listen ports, a fixed 404 default backend) so the
# controller provisions the group's ALB, then a data aws_lb / aws_lb_listener
# lookup -- depends_on the Ingress, the same way Cloud Posse's own component
# does -- so other components (here, apigateway's HTTP API routes) can reach
# its listener without their own copy of the ALB's Terraform state.
#
# Two differences from the Cloud Posse component, both owner decisions for
# this repo:
#
#   1. It creates and owns its own frontend security group instead of
#      letting the controller auto-create one (which defaults to
#      internet-facing 0.0.0.0/0 unless restricted). This component's
#      security group admits only var.admit_security_group_ids, never a
#      CIDR (the repo forbids inbound 0.0.0.0/0 and ::/0), attached via the
#      alb.ingress.kubernetes.io/security-groups annotation. Naming that
#      annotation stops the controller from also managing the backend
#      (node/pod) security group rules on its own, so
#      alb.ingress.kubernetes.io/manage-backend-security-group-rules is set
#      "true" to keep that part automatic -- the same pattern
#      eks-addons/README.md documents for an internet-facing ALB behind
#      CloudFront ("Internet-facing load balancers").
#   2. No `rule` block or backing Kubernetes Service: this component only
#      provisions the shared ALB and its default 404 backend.
#      Per-microservice routing Ingresses join the same group.name and are
#      out of this component's scope.
#
# The scheme stays internal because of two independent enforcements:
#
#   1. spec.ingress_class_name = "alb" below names eks-addons's default
#      IngressClass explicitly (rather than the deprecated
#      kubernetes.io/ingress.class annotation, which the controller still
#      honours but which the DefaultIngressClass admission plugin and the
#      controller's own IngressClass lookup do not resolve the same way --
#      only an Ingress with ingressClassName set to that IngressClass's name
#      gets its ingressClassParams applied). That IngressClass pins
#      ingressClassParams.spec.scheme = internal, which an Ingress cannot
#      override (eks-addons/addons.tf, README.md "Internet-facing load
#      balancers").
#   2. The explicit alb.ingress.kubernetes.io/scheme = internal annotation
#      below, belt-and-braces in case ingressClassParams is ever loosened.

locals {
  enabled = var.enabled

  environment = try(var.tags["Environment"], "default")
  name_prefix = "${local.environment}-${var.group_name}"

  create_namespace = local.enabled && var.create_namespace

  tls_enabled = local.enabled && var.certificate_arn != null

  # HTTPS *instead of* HTTP once certificate_arn is set, never both: a
  # plaintext HTTP:80 listener has no reason to stay reachable next to TLS,
  # and this component has no redirect action to make it safe to leave open.
  listen_ports = local.tls_enabled ? [{ HTTPS = 443 }] : [{ HTTP = 80 }]

  # Comma-separated k=v pairs for alb.ingress.kubernetes.io/tags: the AWS
  # tags the controller applies to the ALB (and to any target group or
  # listener it creates). "Name" is excluded -- the controller's own
  # IngressClassParams sets it, and a conflicting Name tag here breaks the
  # ALB create/update (mirrors the Cloud Posse component's kube_tags local).
  alb_tags_annotation = join(",", [for k, v in var.tags : "${k}=${v}" if k != "Name"])

  default_backend_action_name = "default-404"

  # sg_id x port, one ingress rule each. listen_ports entries are single-key
  # maps ({ HTTP = 80 } or { HTTPS = 443 }); values(...)[0] is the port.
  admitted_rules = {
    for pair in setproduct(var.admit_security_group_ids, [for lp in local.listen_ports : values(lp)[0]]) :
    "${pair[0]}:${pair[1]}" => { source_security_group_id = pair[0], port = pair[1] }
  }
}

data "aws_eks_cluster_auth" "this" {
  count = local.enabled ? 1 : 0

  name = var.cluster_name
}

# ---------------------------------------------------------------------------
# Frontend security group: the ALB's only admitted source is
# var.admit_security_group_ids (never a CIDR block).
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Attached to the ALB via the alb.ingress.kubernetes.io/security-groups annotation on kubernetes_ingress_v1.this; checkov's graph does not follow an annotation reference to aws_security_group.alb[0].id
  count = local.enabled ? 1 : 0

  name_prefix = "${local.name_prefix}-"
  description = "ALB (IngressGroup ${var.group_name}): admits only admit_security_group_ids"
  vpc_id      = var.vpc_id

  tags = { Name = local.name_prefix }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "admitted" {
  for_each = local.enabled ? local.admitted_rules : {}

  security_group_id            = aws_security_group.alb[0].id
  description                  = "Port ${each.value.port} from ${each.value.source_security_group_id}"
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value.source_security_group_id
}

#trivy:ignore:AVD-AWS-0104 Egress is unrestricted by policy (owner decision): the ingress rules above admit only var.admit_security_group_ids, never a CIDR.
resource "aws_vpc_security_group_egress_rule" "all" {
  count = local.enabled ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Never "default" (CKV_K8S_21, validated on var.kubernetes_namespace too):
# created here unless create_namespace = false says it already exists.
resource "kubernetes_namespace_v1" "this" {
  count = local.create_namespace ? 1 : 0

  metadata {
    name   = var.kubernetes_namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# ---------------------------------------------------------------------------
# IngressGroup scaffold: no rules of its own, only the group's shared
# settings and a fixed 404 default backend, so the controller provisions the
# group's ALB.
# ---------------------------------------------------------------------------

resource "kubernetes_ingress_v1" "this" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "${local.name_prefix}-ingress-group"
    namespace = var.kubernetes_namespace

    annotations = merge(
      {
        "alb.ingress.kubernetes.io/scheme"                              = "internal"
        "alb.ingress.kubernetes.io/target-type"                         = "ip"
        "alb.ingress.kubernetes.io/group.name"                          = var.group_name
        "alb.ingress.kubernetes.io/listen-ports"                        = jsonencode(local.listen_ports)
        "alb.ingress.kubernetes.io/security-groups"                     = aws_security_group.alb[0].id
        "alb.ingress.kubernetes.io/manage-backend-security-group-rules" = "true"
        "alb.ingress.kubernetes.io/tags"                                = local.alb_tags_annotation
        "alb.ingress.kubernetes.io/actions.${local.default_backend_action_name}" = jsonencode({
          type = "fixed-response"
          fixedResponseConfig = {
            contentType = "text/plain"
            statusCode  = "404"
            messageBody = "Not Found"
          }
        })
      },
      local.tls_enabled ? {
        "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
        "alb.ingress.kubernetes.io/ssl-policy"      = var.ssl_policy
      } : {}
    )
  }

  spec {
    ingress_class_name = var.ingress_class_name

    default_backend {
      service {
        name = local.default_backend_action_name
        port {
          name = "use-annotation"
        }
      }
    }
  }

  wait_for_load_balancer = var.wait_for_load_balancer

  depends_on = [
    aws_vpc_security_group_ingress_rule.admitted,
    aws_vpc_security_group_egress_rule.all,
    kubernetes_namespace_v1.this,
  ]
}

# ---------------------------------------------------------------------------
# ALB lookup: no Terraform resource creates the ALB itself (the controller
# does, from the Ingress above); it is found the same way Cloud Posse's own
# component finds it, by the tags the controller applies to it.
# ---------------------------------------------------------------------------

data "aws_lb" "this" {
  count = local.enabled ? 1 : 0

  tags = {
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = var.group_name
    "elbv2.k8s.aws/cluster"    = var.cluster_name
  }

  depends_on = [kubernetes_ingress_v1.this]
}

data "aws_lb_listener" "http" {
  count = local.enabled && !local.tls_enabled ? 1 : 0

  load_balancer_arn = data.aws_lb.this[0].arn
  port              = 80
}

data "aws_lb_listener" "https" {
  count = local.tls_enabled ? 1 : 0

  load_balancer_arn = data.aws_lb.this[0].arn
  port              = 443
}
