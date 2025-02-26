locals {
  dns_domains = var.dns_domains
}

resource "aws_acm_certificate" "main" {
  for_each = local.dns_domains

  domain_name               = each.value.domain_name
  subject_alternative_names = lookup(each.value, "subject_alternative_names", [])
  validation_method         = lookup(each.value, "validation_method", "DNS")

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${replace(each.value.domain_name, ".", "-")}"
    }
  )
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in flatten([
      for domain_key, domain in local.dns_domains : [
        for dvo in aws_acm_certificate.main[domain_key].domain_validation_options : {
          domain_key = domain_key
          dvo        = dvo
        }
      ]
    ]) : "${dvo.domain_key}.${dvo.dvo.domain_name}" => dvo
  }

  zone_id         = var.zone_id
  name            = each.value.dvo.resource_record_name
  type            = each.value.dvo.resource_record_type
  ttl             = 60
  records         = [each.value.dvo.resource_record_value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  for_each = {
    for domain_key, domain in local.dns_domains : domain_key => domain
    if lookup(domain, "wait_for_validation", true)
  }

  certificate_arn         = aws_acm_certificate.main[each.key].arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.main[each.key].domain_validation_options : dvo.resource_record_name]

  depends_on = [aws_route53_record.validation]
}