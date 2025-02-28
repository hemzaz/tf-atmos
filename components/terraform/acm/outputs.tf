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

output "certificate_keys" {
  description = <<-EOT
    IMPORTANT: AWS does not allow private key export through the API.
    Use the export-cert.sh script in /scripts/certificates/ with:
    ./scripts/certificates/export-cert.sh -a <CERTIFICATE_ARN> -r <REGION> -u
    This output is a placeholder and cannot be used directly.
  EOT
  value = {
    for k, v in aws_acm_certificate.main : k => "NOT_EXPORTABLE_FROM_ACM_API__USE_EXPORT_SCRIPT_IN_SCRIPTS_DIRECTORY"
  }
  sensitive = true
}

output "certificate_crts" {
  description = <<-EOT
    IMPORTANT: AWS does not allow certificate content export through the API.
    Use the export-cert.sh script in /scripts/certificates/ with:
    ./scripts/certificates/export-cert.sh -a <CERTIFICATE_ARN> -r <REGION> -u
    This output is a placeholder and cannot be used directly.
  EOT
  value = {
    for k, v in aws_acm_certificate.main : k => "NOT_EXPORTABLE_FROM_ACM_API__USE_EXPORT_SCRIPT_IN_SCRIPTS_DIRECTORY"
  }
  sensitive = true
}

output "export_instructions" {
  description = "Instructions for exporting certificates from ACM"
  value = <<-EOT
    CERTIFICATE EXPORT INSTRUCTIONS:
    
    AWS ACM does not allow certificate export through the API. To export your certificates:
    
    1. Use the provided script in the scripts/certificates/ directory:
       ./scripts/certificates/export-cert.sh -a <CERTIFICATE_ARN> -r <REGION> -u
    
    2. This will export the certificate files locally and optionally upload them
       to AWS Secrets Manager with the -u flag.
    
    3. To use certificates with External Secrets in Kubernetes, set:
       use_external_secrets = true
       secrets_manager_secret_path = "certificates/your-domain-cert"
    
    4. Do NOT attempt to use certificate_keys or certificate_crts outputs directly 
       as they contain placeholder values only.
  EOT
}