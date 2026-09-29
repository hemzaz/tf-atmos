locals {
  dns_domains = var.dns_domains

  # Validate that if tags contains an Environment key, we can use it
  environment = try(var.tags["Environment"], "unknown")

  # One Route53 validation record per distinct validation name. ACM gives a
  # name and its wildcard (x and *.x) the same CNAME, and the same name the
  # same CNAME in every certificate, so the records are keyed by the name
  # without its "*." -- one key per resource_record_name. The record names
  # themselves are only known once a certificate exists, so they cannot be
  # for_each keys; these come from configuration. Cloud Posse's
  # acm-request-certificate does the same (count over the distinct names).
  # Value: the first DNS-validated certificate that carries the name.
  validation_names = {
    for name in distinct(flatten([
      for key, domain in local.dns_domains : [
        for n in concat([domain.domain_name], domain.subject_alternative_names) : trimprefix(lower(n), "*.")
      ] if domain.validation_method == "DNS"
    ])) :
    name => [
      for key, domain in local.dns_domains : key
      if domain.validation_method == "DNS" && contains([
        for n in concat([domain.domain_name], domain.subject_alternative_names) : trimprefix(lower(n), "*.")
      ], name)
    ][0]
  }

  # That certificate's validation option for the name (x and *.x share it).
  validation_options = {
    for name, key in local.validation_names : name => [
      for dvo in aws_acm_certificate.main[key].domain_validation_options : dvo
      if trimprefix(lower(dvo.domain_name), "*.") == name
    ][0]
  }
}

resource "aws_acm_certificate" "main" {
  for_each = local.dns_domains

  domain_name               = each.value.domain_name
  subject_alternative_names = lookup(each.value, "subject_alternative_names", [])
  validation_method         = lookup(each.value, "validation_method", "DNS")

  # Use this to export the certificate details
  options {
    certificate_transparency_logging_preference = var.cert_transparency_logging ? "ENABLED" : "DISABLED"
  }

  lifecycle {
    create_before_destroy = true

    # Add precondition checks to ensure domain and validation method are valid
    precondition {
      condition     = can(regex("^(\\*\\.)?([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", each.value.domain_name))
      error_message = "Domain name ${each.value.domain_name} is not valid. It must be a valid DNS domain name."
    }

    precondition {
      condition     = contains(["DNS", "EMAIL"], each.value.validation_method)
      error_message = "Validation method must be either DNS or EMAIL."
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name       = "${local.environment}-${replace(each.value.domain_name, ".", "-")}"
      DomainName = each.value.domain_name
      CreatedBy  = "terraform"
      Component  = "acm"
    }
  )
}

resource "aws_route53_record" "validation" {
  for_each = local.validation_names

  zone_id         = var.zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  ttl             = 60
  records         = [local.validation_options[each.key].resource_record_value]
  allow_overwrite = true

  lifecycle {
    precondition {
      condition     = var.zone_id != ""
      error_message = "Route53 zone_id must be provided for DNS validation"
    }
  }
}

resource "aws_acm_certificate_validation" "main" {
  for_each = {
    for domain_key, domain in local.dns_domains : domain_key => domain
    if lookup(domain, "wait_for_validation", true) && domain.validation_method == "DNS"
  }

  certificate_arn         = aws_acm_certificate.main[each.key].arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.main[each.key].domain_validation_options : dvo.resource_record_name]

  # Add a timeout to ensure enough time for DNS propagation
  timeouts {
    create = "45m"
  }

  depends_on = [aws_route53_record.validation]

  lifecycle {
    # Verify validation records exist
    precondition {
      condition     = length([for dvo in aws_acm_certificate.main[each.key].domain_validation_options : dvo.resource_record_name]) > 0
      error_message = "No validation records found for certificate ${each.key}. Check that the domain is configured correctly."
    }

    # Verify every distinct validation record name of THIS certificate has a
    # record. (The previous check counted every record in the instance, so any
    # instance with two or more certificates failed here.)
    precondition {
      condition = length(setsubtract(
        toset([for dvo in aws_acm_certificate.main[each.key].domain_validation_options : trimsuffix(lower(dvo.resource_record_name), ".")]),
        toset([for record in aws_route53_record.validation : trimsuffix(lower(record.name), ".")])
      )) == 0
      error_message = "Not all validation records have been created for certificate ${each.key}. DNS validation may fail."
    }

    # Add post-condition to verify certificate was successfully validated
    postcondition {
      condition     = aws_acm_certificate.main[each.key].status == "ISSUED" || aws_acm_certificate.main[each.key].status == "PENDING_VALIDATION"
      error_message = "Certificate ${each.key} validation failed. Current status: ${aws_acm_certificate.main[each.key].status}"
    }
  }
}