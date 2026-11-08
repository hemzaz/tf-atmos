# =============================================================================
# TFLint Configuration for Terraform Code Quality
# =============================================================================

config {
  call_module_type = "local"
  force = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Security rules
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# AWS-specific rules
rule "aws_instance_invalid_type" {
  enabled = true
}

# Off: components tag resources through provider default_tags built from
# var.tags, and `atmos terraform lint` runs tflint without stack vars, so
# var.tags is empty there and every resource looks untagged.
rule "aws_resource_missing_tags" {
  enabled = false
}

# House file (scripts/check-vendor.py TFLINT): the repository's .tflint.hcl above,
# verbatim, for `atmos terraform lint`, which prefers this file to the root one.
# Vendored Cloud Posse aws-config v3.1.1 remote-state.tf (module
# global_collector_region, which remote-state_override.tf bypasses) calls
# lookup() with 2 arguments; Cloud Posse code is not edited here.
rule "terraform_deprecated_lookup" {
  enabled = false
}
