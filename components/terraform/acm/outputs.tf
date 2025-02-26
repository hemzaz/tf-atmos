output "certificate_arns" {
  description = "Map of domain names to certificate ARNs"
  value = {
    for k, v in aws_acm_certificate.main : k => v.arn
  }
}

output "certificate_domains" {
  description = "Map of certificate names to domain names"
  value = {
    for k, v in aws_acm_certificate.main : k => v.domain_name
  }
}

output "certificate_validation_ids" {
  description = "Map of domain names to certificate validation IDs"
  value = {
    for k, v in aws_acm_certificate_validation.main : k => v.id
  }
}