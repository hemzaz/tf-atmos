# Account Verification
#
# Verifies that Terraform is executing in the correct target AWS account by comparing the current
# AWS account ID against the expected account ID based on the component's context (tenant-stage).
#
# How it works:
# 1. Constructs the expected account name from context variables (format: "tenant-stage")
# 2. Looks up the expected account ID from the account_map
# 3. Validates that current account ID matches expected account ID
# 4. Fails with a clear error message if accounts don't match
#
# Note: Validation only occurs when account_verification_enabled is true, the account_map is
# populated, and the expected account name can be constructed from tenant and stage variables.

locals {
  # Construct expected account name in the format "tenant-stage".
  # Only construct if both tenant and stage are non-null and non-empty strings.
  expected_account_name = (
    var.account_verification_enabled &&
    try(var.tenant, null) != null &&
    try(var.stage, null) != null &&
    try(var.tenant, "") != "" &&
    try(var.stage, "") != ""
  ) ? "${var.tenant}-${var.stage}" : null

  # Look up the expected account ID from account_map using the expected account name.
  # Returns null if account name cannot be constructed or if the name is not found in the map.
  expected_account_id = try(
    local.expected_account_name != null ? local.account_map[local.expected_account_name] : null,
    null
  )

  # Determine if validation should be performed based on:
  # 1. account_verification_enabled is true
  # 2. account_map is provided and not empty
  # 3. Expected account name can be constructed from tenant and stage
  # 4. Expected account ID exists in the account_map for the constructed account name
  should_verify_account = (
    local.enabled &&
    var.account_verification_enabled &&
    length(local.account_map) > 0 &&
    local.expected_account_name != null &&
    local.expected_account_id != null
  )

  # Error message for account mismatch.
  account_verification_error = local.should_verify_account && local.current_account_id != local.expected_account_id ? (
    "Account verification failed: Expected account ID ${local.expected_account_id} for account '${local.expected_account_name}' (tenant: ${var.tenant}, stage: ${var.stage}), but current account ID is ${local.current_account_id}"
  ) : "Account verification passed"
}

# Perform account verification using terraform_data resource with lifecycle precondition.
# The precondition ensures that the current account ID matches the expected account ID,
# failing the Terraform run with a descriptive error if there's a mismatch.
resource "terraform_data" "account_verification" {
  count = local.should_verify_account ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.current_account_id == local.expected_account_id
      error_message = local.account_verification_error
    }
  }
}
