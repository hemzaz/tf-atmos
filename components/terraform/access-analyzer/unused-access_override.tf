# House override of the vendored Cloud Posse aws-access-analyzer v2.0.1 (vendor.yaml) main.tf
# (E5c7, owner decision 2026-11-14). Terraform replaces a nested block of an overridden resource
# whole, so this configuration repeats CP's unused_access_age and adds the analysis rule of
# unused-access-exclusions_house.tf when it names accounts; with none it is CP's block. The AWS
# provider makes configuration ForceNew: a changed exclusion list replaces the analyzer, which
# regenerates its findings (archived ones lose their status). The account checks are the variable's
# validations (an override cannot add preconditions).
resource "aws_accessanalyzer_analyzer" "organization_unused_access" {
  configuration {
    unused_access {
      unused_access_age = var.unused_access_age

      dynamic "analysis_rule" {
        for_each = length(local.unused_access_exclusion_account_ids) > 0 ? [1] : []
        content {
          exclusion {
            account_ids = local.unused_access_exclusion_account_ids
          }
        }
      }
    }
  }
}
