output "email_identity" {
  description = "The verified domain (null when disabled)"
  value       = one(aws_sesv2_email_identity.this[*].email_identity)
}

output "email_identity_arn" {
  description = "ARN of the SES email identity, for IAM policies that send from it (ses:SendEmail, ses:SendRawEmail)"
  value       = one(aws_sesv2_email_identity.this[*].arn)
}

output "verified_for_sending_status" {
  description = "Whether SES has verified the identity and it can send (false until the DKIM records resolve; read after the next refresh)"
  value       = one(aws_sesv2_email_identity.this[*].verified_for_sending_status)
}

output "dkim_status" {
  description = "Easy DKIM verification status: PENDING, SUCCESS, FAILED, TEMPORARY_FAILURE or NOT_STARTED"
  value       = one(flatten(aws_sesv2_email_identity.this[*].dkim_signing_attributes[*].status))
}

output "dkim_records" {
  description = "The three DKIM CNAME records (name => value), written into zone_id or, without one, to publish by hand"
  value       = { for t in local.dkim_tokens : "${t}._domainkey.${var.domain}" => "${t}.dkim.amazonses.com" }
}
