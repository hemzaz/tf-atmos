# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_sesv2_email_identity" {
    defaults = {
      arn                         = "arn:aws:ses:eu-west-2:123456789012:identity/example.com"
      verified_for_sending_status = false
      # A nested block: the mock takes one object, applied to each element.
      dkim_signing_attributes = {
        current_signing_key_length    = "RSA_2048_BIT"
        domain_signing_private_key    = null
        domain_signing_selector       = null
        last_key_generation_timestamp = "2026-09-25T00:00:00Z"
        next_signing_key_length       = "RSA_2048_BIT"
        signing_attributes_origin     = "AWS_SES"
        status                        = "PENDING"
        tokens                        = ["tokena", "tokenb", "tokenc"]
      }
    }
  }
}

variables {
  region  = "eu-west-2"
  domain  = "example.com"
  zone_id = "Z0123456789ABCDEFGHIJ"
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

run "domain_identity_with_easy_dkim" {
  command = plan

  assert {
    condition     = aws_sesv2_email_identity.this[0].email_identity == "example.com"
    error_message = "The identity is the domain."
  }

  assert {
    condition     = aws_sesv2_email_identity.this[0].dkim_signing_attributes[0].next_signing_key_length == "RSA_2048_BIT"
    error_message = "Easy DKIM with Cloud Posse's 2048-bit key by default."
  }

  assert {
    condition     = length(aws_route53_record.dkim) == 3 && alltrue([for r in aws_route53_record.dkim : r.zone_id == "Z0123456789ABCDEFGHIJ" && r.type == "CNAME" && r.ttl == 1800])
    error_message = "Three DKIM CNAME records go into the given zone."
  }
}

run "dkim_records_point_at_ses" {
  command = apply

  assert {
    condition     = [for r in aws_route53_record.dkim : r.name] == ["tokena._domainkey.example.com", "tokenb._domainkey.example.com", "tokenc._domainkey.example.com"]
    error_message = "Each record is <token>._domainkey.<domain>."
  }

  assert {
    condition     = [for r in aws_route53_record.dkim : one(r.records)] == ["tokena.dkim.amazonses.com", "tokenb.dkim.amazonses.com", "tokenc.dkim.amazonses.com"]
    error_message = "Each record points at <token>.dkim.amazonses.com."
  }

  assert {
    condition     = output.email_identity_arn == "arn:aws:ses:eu-west-2:123456789012:identity/example.com" && output.verified_for_sending_status == false && output.dkim_status == "PENDING"
    error_message = "The outputs carry the identity ARN and its verification state."
  }

  assert {
    condition     = output.dkim_records["tokena._domainkey.example.com"] == "tokena.dkim.amazonses.com"
    error_message = "dkim_records lists the records for manual publication."
  }
}

run "no_zone_writes_no_records" {
  command = plan

  variables {
    zone_id = null
  }

  assert {
    condition     = length(aws_route53_record.dkim) == 0 && length(aws_sesv2_email_identity.this) == 1
    error_message = "Without zone_id the identity is created and no records are written."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_sesv2_email_identity.this) == 0 && length(aws_route53_record.dkim) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.email_identity_arn == null && output.dkim_records == {}
    error_message = "Outputs are null or empty when disabled."
  }
}

run "rejects_a_non_domain" {
  command = plan

  variables {
    domain = "https://Example.com/"
  }

  expect_failures = [var.domain]
}

run "rejects_a_bad_zone_id" {
  command = plan

  variables {
    zone_id = "example.com"
  }

  expect_failures = [var.zone_id]
}

run "rejects_an_unknown_key_length" {
  command = plan

  variables {
    dkim_signing_key_length = "RSA_4096_BIT"
  }

  expect_failures = [var.dkim_signing_key_length]
}
