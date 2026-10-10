# Mock-provider tests for DNS validation: no AWS credentials, no network. Run
# from the component directory with `terraform init -backend=false && terraform test`.
#
# Validation records are keyed by validation name (the domain without "*."),
# one per resource_record_name: a name and its wildcard share one record. The
# per-certificate precondition on aws_acm_certificate_validation.main requires
# a record for every distinct resource_record_name of that certificate's
# validation options. (It used to count every record in the instance, so an
# instance with two or more certificates failed at apply.)
#
# Each run overrides each certificate instance's domain_validation_options,
# as the AWS provider would report them. override_during = plan makes them
# known at plan, so the records and the precondition are evaluated there
# (command = apply would regenerate the other mocked computed attributes and
# fail with "inconsistent final plan").

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn    = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      status = "ISSUED"
    }
  }
}

variables {
  region  = "us-east-1"
  zone_id = "Z1234567890ABCDEFGHIJ"
  tags = {
    Environment = "test"
  }
}

run "one_certificate" {
  command = plan

  variables {
    dns_domains = {
      api = { domain_name = "api.example.com" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["api.example.com"]
    error_message = "One certificate gets one validation record, keyed by its validation name."
  }

  assert {
    condition     = aws_route53_record.validation["api.example.com"].name == "_a1.api.example.com." && aws_route53_record.validation["api.example.com"].zone_id == var.zone_id
    error_message = "The record is the certificate's validation CNAME, in var.zone_id."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["api"]
    error_message = "The certificate is validated (its precondition held)."
  }
}

run "two_certificates" {
  command = plan

  variables {
    dns_domains = {
      api    = { domain_name = "api.example.com" }
      assets = { domain_name = "assets.example.com" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["assets"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "assets.example.com", resource_record_name = "_b2.assets.example.com.", resource_record_type = "CNAME", resource_record_value = "_v2.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = toset(keys(aws_route53_record.validation)) == toset(["api.example.com", "assets.example.com"])
    error_message = "Each certificate gets its own validation record."
  }

  assert {
    condition     = toset(keys(aws_acm_certificate_validation.main)) == toset(["api", "assets"])
    error_message = "Both certificates are validated: each precondition checks only its own records."
  }
}

run "wildcard_and_apex_share_one_record" {
  command = plan

  variables {
    dns_domains = {
      main = { domain_name = "*.example.com", subject_alternative_names = ["example.com"] }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["main"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "*.example.com", resource_record_name = "_c3.example.com.", resource_record_type = "CNAME", resource_record_value = "_v3.acm-validations.aws." },
        { domain_name = "example.com", resource_record_name = "_c3.example.com.", resource_record_type = "CNAME", resource_record_value = "_v3.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["example.com"]
    error_message = "*.example.com and example.com share one validation record, so there is one resource."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["main"]
    error_message = "The certificate is validated by the shared record."
  }
}

run "email_validation_creates_no_records" {
  command = plan

  variables {
    dns_domains = {
      api    = { domain_name = "api.example.com" }
      legacy = { domain_name = "legacy.example.com", validation_method = "EMAIL" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["api.example.com"]
    error_message = "EMAIL-validated certificates get no Route53 validation records."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["api"]
    error_message = "Only DNS-validated certificates are waited on."
  }
}

# The precondition can fail: a validation option whose record name has no
# record (here one the configuration does not carry) stops the validation.
run "missing_record_fails_the_precondition" {
  command = plan

  variables {
    dns_domains = {
      api = { domain_name = "api.example.com" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
        { domain_name = "other.example.com", resource_record_name = "_d4.other.example.com.", resource_record_type = "CNAME", resource_record_value = "_v4.acm-validations.aws." },
      ]
    }
  }

  expect_failures = [aws_acm_certificate_validation.main]
}

# A DR certificate validated by another state's record (process_domain_validation_options
# = false) writes no record of its own, needs no zone_id, and is still waited on
# without the per-certificate record precondition. A certificate beside it that
# processes its options keeps its record.
run "unprocessed_certificate_writes_no_record" {
  command = plan

  variables {
    zone_id = ""
    dns_domains = {
      api = { domain_name = "api.example.com", process_domain_validation_options = false }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 0
    error_message = "An unprocessed certificate writes no validation record."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["api"]
    error_message = "An unprocessed certificate is still waited on."
  }

  assert {
    condition     = aws_acm_certificate_validation.main["api"].validation_record_fqdns == toset(["_a1.api.example.com."])
    error_message = "The wait names the certificate's own validation record."
  }
}

run "unprocessed_beside_processed" {
  command = plan

  variables {
    dns_domains = {
      api    = { domain_name = "api.example.com", process_domain_validation_options = false }
      assets = { domain_name = "assets.example.com" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["assets"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "assets.example.com", resource_record_name = "_b2.assets.example.com.", resource_record_type = "CNAME", resource_record_value = "_v2.acm-validations.aws." },
      ]
    }
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["assets.example.com"]
    error_message = "Only the processed certificate gets a validation record."
  }

  assert {
    condition     = toset(keys(aws_acm_certificate_validation.main)) == toset(["api", "assets"])
    error_message = "Both certificates are waited on."
  }
}

# zone_id may be empty only when no DNS certificate processes its options.
run "processed_certificate_needs_zone_id" {
  command = plan

  variables {
    zone_id = ""
    dns_domains = {
      api = { domain_name = "api.example.com" }
    }
  }

  override_resource {
    target          = aws_acm_certificate.main["api"]
    override_during = plan
    values = {
      status = "ISSUED"
      domain_validation_options = [
        { domain_name = "api.example.com", resource_record_name = "_a1.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_v1.acm-validations.aws." },
      ]
    }
  }

  expect_failures = [var.zone_id]
}
