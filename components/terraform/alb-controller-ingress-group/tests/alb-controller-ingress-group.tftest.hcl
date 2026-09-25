# Mock-provider tests: no AWS credentials, no cluster access. Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_data {
    target = data.aws_eks_cluster_auth.this
    values = {
      token = "mock-token"
    }
  }
  override_data {
    target          = data.aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/test-group/0123456789abcdef"
      dns_name = "test-group-0123456789.eu-west-2.elb.amazonaws.com"
      zone_id  = "Z215JYRZR1TBD5"
    }
  }
  override_data {
    target          = data.aws_lb_listener.http
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/test-group/0123456789abcdef/1111111111111111"
    }
  }
  override_data {
    target          = data.aws_lb_listener.https
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/test-group/0123456789abcdef/2222222222222222"
    }
  }
  mock_resource "aws_security_group" {
    override_during = plan
    defaults = {
      id = "sg-0000000000000000f"
    }
  }
}

mock_provider "kubernetes" {}

variables {
  region                   = "eu-west-2"
  cluster_name             = "testenv-01-microservices"
  host                     = "https://ABCDEF0123456789.gr7.eu-west-2.eks.amazonaws.com"
  cluster_ca_certificate   = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCg=="
  vpc_id                   = "vpc-0123456789abcdef0"
  group_name               = "microservices-http"
  admit_security_group_ids = ["sg-0123456789abcdef0"]
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "annotations_carry_the_group_name_and_internal_scheme" {
  command = plan

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/group.name"] == "microservices-http"
    error_message = "The Ingress must carry the IngressGroup name."
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/scheme"] == "internal"
    error_message = "The Ingress must be explicitly internal, never internet-facing."
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/manage-backend-security-group-rules"] == "true"
    error_message = "An explicit alb.ingress.kubernetes.io/security-groups annotation stops the controller managing backend (node/pod) SG rules on its own; this annotation must opt back in."
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].spec[0].ingress_class_name == "alb"
    error_message = "The Ingress must reference the IngressClass via spec.ingress_class_name (default \"alb\"), not the deprecated kubernetes.io/ingress.class annotation, so eks-addons's ingressClassParams (the internal-scheme pin) actually applies."
  }

  assert {
    condition     = !contains(keys(kubernetes_ingress_v1.this[0].metadata[0].annotations), "kubernetes.io/ingress.class")
    error_message = "The deprecated kubernetes.io/ingress.class annotation must not be set alongside spec.ingress_class_name."
  }
}

run "creates_a_non_default_namespace_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_namespace_v1.this) == 1 && kubernetes_namespace_v1.this[0].metadata[0].name == "alb-ingress-group"
    error_message = "kubernetes_namespace defaults to a purpose-named namespace, never \"default\" (CKV_K8S_21), and is created unless create_namespace = false."
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].namespace == "alb-ingress-group"
    error_message = "The Ingress is created in var.kubernetes_namespace."
  }
}

run "create_namespace_false_skips_it" {
  command = plan

  variables {
    create_namespace = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.this) == 0
    error_message = "create_namespace = false creates no kubernetes_namespace resource (it already exists)."
  }
}

run "rejects_the_default_namespace" {
  command = plan

  variables {
    kubernetes_namespace = "default"
  }

  expect_failures = [var.kubernetes_namespace]
}

run "listen_ports_default_to_http_only" {
  command = plan

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/listen-ports"] == jsonencode([{ HTTP = 80 }])
    error_message = "Without certificate_arn, only an HTTP (80) listener is requested."
  }

  assert {
    condition     = length(data.aws_lb_listener.https) == 0 && output.https_listener_arn == null
    error_message = "No HTTPS listener lookup without certificate_arn."
  }

  assert {
    condition     = length(data.aws_lb_listener.http) == 1
    error_message = "Without certificate_arn, the HTTP listener lookup exists (it is the only listener)."
  }

  assert {
    condition     = output.member_listen_ports_annotation == jsonencode([{ HTTP = 80 }])
    error_message = "member_listen_ports_annotation must equal this component's own listen-ports annotation, so a member Ingress can copy it exactly."
  }
}

run "https_listener_when_certificate_arn_is_set" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/listen-ports"] == jsonencode([{ HTTPS = 443 }])
    error_message = "certificate_arn replaces the HTTP (80) listener with HTTPS (443); it never opens both."
  }

  assert {
    condition     = kubernetes_ingress_v1.this[0].metadata[0].annotations["alb.ingress.kubernetes.io/certificate-arn"] == var.certificate_arn
    error_message = "certificate_arn reaches the certificate-arn annotation."
  }

  assert {
    condition     = length(data.aws_lb_listener.https) == 1
    error_message = "certificate_arn adds the HTTPS listener lookup."
  }

  assert {
    condition     = length(data.aws_lb_listener.http) == 0 && output.http_listener_arn == null
    error_message = "certificate_arn removes the HTTP listener lookup: no plaintext listener stays reachable once TLS is on."
  }

  assert {
    condition     = output.member_listen_ports_annotation == jsonencode([{ HTTPS = 443 }])
    error_message = "member_listen_ports_annotation must equal this component's own HTTPS-only listen-ports annotation once certificate_arn is set, so a member Ingress that copies it never falls back to the merged default HTTP:80 listener."
  }
}

run "certificate_arn_admits_no_port_80_ingress_rule" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length([for r in aws_vpc_security_group_ingress_rule.admitted : r if r.from_port == 80]) == 0
    error_message = "Port 80 must not be admitted on the frontend security group once certificate_arn is set: there is no HTTP listener left for it to reach."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.admitted : r.from_port == 443])
    error_message = "With certificate_arn set, every admitted ingress rule is on port 443 (HTTPS only)."
  }
}

run "security_group_admits_only_the_given_security_groups_never_a_cidr" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.admitted) == 1
    error_message = "One ingress rule per admit_security_group_ids x listen_ports pair; one SG, one port (HTTP only) here."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.admitted : r.referenced_security_group_id == "sg-0123456789abcdef0"])
    error_message = "Every ingress rule must reference an admitted security group, not a CIDR."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.admitted : r.cidr_ipv4 == null && r.cidr_ipv6 == null])
    error_message = "No ingress rule may carry a CIDR block; the repo forbids inbound 0.0.0.0/0 and ::/0."
  }
}

run "two_admitted_security_groups_and_tls_creates_two_ingress_rules" {
  command = plan

  variables {
    admit_security_group_ids = ["sg-0123456789abcdef0", "sg-0123456789abcdef1"]
    certificate_arn          = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.admitted) == 2
    error_message = "2 security groups x 1 port (HTTPS only, certificate_arn replaces HTTP rather than adding to it) = 2 ingress rules."
  }
}

run "rejects_empty_admit_security_group_ids" {
  command = plan

  variables {
    admit_security_group_ids = []
  }

  expect_failures = [var.admit_security_group_ids]
}

run "rejects_a_cidr_block_instead_of_a_security_group" {
  command = plan

  variables {
    admit_security_group_ids = ["0.0.0.0/0"]
  }

  expect_failures = [var.admit_security_group_ids]
}

run "rejects_an_invalid_group_name" {
  command = plan

  variables {
    group_name = "Not Valid!"
  }

  expect_failures = [var.group_name]
}

run "rejects_an_empty_ingress_class_name" {
  command = plan

  variables {
    ingress_class_name = ""
  }

  expect_failures = [var.ingress_class_name]
}

run "rejects_an_invalid_ingress_class_name" {
  command = plan

  variables {
    ingress_class_name = "Not Valid!"
  }

  expect_failures = [var.ingress_class_name]
}

run "outputs_are_wired_to_the_load_balancer_lookup" {
  # data.aws_lb/data.aws_lb_listener depend_on the Ingress by design (the
  # ALB does not exist until the controller creates it), so their values are
  # unknown under `plan` -- assert the lookups and their outputs exist and
  # are wired up, not their literal values (that needs `apply`, which the
  # mock kubernetes/aws providers cannot carry through this component's
  # cross-provider depends_on consistently).
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.group_name == "microservices-http"
    error_message = "group_name output echoes var.group_name."
  }

  assert {
    condition     = length(data.aws_lb.this) == 1
    error_message = "data.aws_lb.this looks up the controller-provisioned ALB."
  }

  assert {
    condition     = length(data.aws_lb_listener.http) == 0 && length(data.aws_lb_listener.https) == 1
    error_message = "Only the HTTPS listener lookup exists when certificate_arn is set; the HTTP one is not (no plaintext listener to look up)."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(kubernetes_ingress_v1.this) == 0 && length(aws_security_group.alb) == 0 && length(aws_vpc_security_group_ingress_rule.admitted) == 0 && length(kubernetes_namespace_v1.this) == 0
    error_message = "enabled = false creates no Ingress, security group, ingress rules or namespace."
  }

  assert {
    condition     = output.group_name == null && output.load_balancer_arn == null && output.http_listener_arn == null
    error_message = "Outputs are null when disabled."
  }
}
