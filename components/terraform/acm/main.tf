locals {
  dns_domains = var.dns_domains

  # Validate that if tags contains an Environment key, we can use it
  environment = try(var.tags["Environment"], "unknown")
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
      condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", each.value.domain_name))
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
  for_each = {
    for dvo in flatten([
      for domain_key, domain in local.dns_domains : [
        for dvo in aws_acm_certificate.main[domain_key].domain_validation_options : {
          domain_key = domain_key
          dvo        = dvo
        }
      ] if domain.validation_method == "DNS"
    ]) : "${dvo.domain_key}.${dvo.dvo.domain_name}" => dvo
  }

  zone_id         = var.zone_id
  name            = each.value.dvo.resource_record_name
  type            = each.value.dvo.resource_record_type
  ttl             = 60
  records         = [each.value.dvo.resource_record_value]
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
    
    # Verify all validation records have been created
    precondition {
      condition     = length([for dvo in aws_acm_certificate.main[each.key].domain_validation_options : dvo.resource_record_name]) == 
                      length([for record in aws_route53_record.validation : record.name if contains(keys(aws_route53_record.validation), "${each.key}.${aws_acm_certificate.main[each.key].domain_name}")])
      error_message = "Not all validation records have been created for certificate ${each.key}. DNS validation may fail."
    }
    
    # Add post-condition to verify certificate was successfully validated
    postcondition {
      condition     = aws_acm_certificate.main[each.key].status == "ISSUED" || aws_acm_certificate.main[each.key].status == "PENDING_VALIDATION"
      error_message = "Certificate ${each.key} validation failed. Current status: ${aws_acm_certificate.main[each.key].status}"
    }
  }
}