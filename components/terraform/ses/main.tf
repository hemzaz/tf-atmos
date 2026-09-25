# One SES domain identity per instance, modelled on Cloud Posse's aws-ses
# component (which wraps cloudposse/ses). Written as plain resources on the
# SES v2 API, like the other root components: an Easy DKIM email identity,
# verified through three CNAME records written into the domain's public
# Route 53 zone. No SMTP IAM user is created (see the README).

locals {
  enabled        = var.enabled
  create_records = local.enabled && var.ses_verify_dkim && var.zone_id != null

  # Easy DKIM always issues three tokens.
  dkim_tokens = local.enabled ? aws_sesv2_email_identity.this[0].dkim_signing_attributes[0].tokens : []
}

resource "aws_sesv2_email_identity" "this" {
  count = local.enabled ? 1 : 0

  email_identity = var.domain

  dkim_signing_attributes {
    next_signing_key_length = var.dkim_signing_key_length
  }

  tags = { Name = var.domain }
}

resource "aws_route53_record" "dkim" {
  count = local.create_records ? 3 : 0

  zone_id = var.zone_id
  name    = "${local.dkim_tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = var.dkim_record_ttl
  records = ["${local.dkim_tokens[count.index]}.dkim.amazonses.com"]
}
