# Mock-provider tests for DNS validation: no AWS credentials, no network. Run
# from the component directory with `terraform init -backend=false && terraform test`.
#
# The per-certificate "all validation records created" precondition on
# aws_acm_certificate_validation.main used to count every validation record in
# the instance, so an instance with two or more certificates (the
# serverless-api template's api + assets) failed at apply. These runs apply one
# and two certificates and pass only if that precondition holds for each.
#
# The mock gives every certificate the same domain_validation_options (mocks
# are per resource, not per instance). It names api.example.com, the first
# certificate's domain: with the old count, certificate "api" saw both records
# (2 != its 1 DVO) and "assets" saw none, so the two-certificate run failed.
# override_during = plan makes the mocked DVOs known at plan, as the AWS
# provider's own CustomizeDiff does for the keys, so the validation records'
# for_each can be planned.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn    = "arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      status = "ISSUED"
      domain_validation_options = [
        {
          domain_name           = "api.example.com"
          resource_record_name  = "_0123456789abcdef.api.example.com."
          resource_record_type  = "CNAME"
          resource_record_value = "_fedcba9876543210.acm-validations.aws."
        },
      ]
    }
  }
}

variables {
  region  = "eu-west-2"
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

  assert {
    condition     = keys(aws_route53_record.validation) == ["api.api.example.com"]
    error_message = "One certificate gets one validation record, keyed <certificate>.<dvo domain>."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["api"]
    error_message = "The certificate is validated (its precondition held)."
  }

  assert {
    condition     = aws_route53_record.validation["api.api.example.com"].zone_id == var.zone_id
    error_message = "Validation records go in var.zone_id."
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

  assert {
    condition     = length(aws_route53_record.validation) == 2
    error_message = "Each certificate gets its own validation record."
  }

  assert {
    condition     = toset(keys(aws_acm_certificate_validation.main)) == toset(["api", "assets"])
    error_message = "Both certificates are validated: each precondition counts only its own records."
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

  assert {
    condition     = keys(aws_route53_record.validation) == ["api.api.example.com"]
    error_message = "EMAIL-validated certificates get no Route53 validation records."
  }

  assert {
    condition     = keys(aws_acm_certificate_validation.main) == ["api"]
    error_message = "Only DNS-validated certificates are waited on."
  }
}
