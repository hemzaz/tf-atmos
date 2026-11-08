# House override of the vendored Cloud Posse account-verification mixin
# (aws-cloudtrail-mixins v0.5.0, vendor.yaml: account-verification.mixin.tf).
# Terraform replaces the named locals of that file's locals block with these.
#
# Why (owner decision 2026-11-07, E5b): upstream expects the account
# "<tenant>-<stage>", the Cloud Posse convention of one account per stage.
# fnx-ew1-prod runs in the prod-eu account with stage prod
# (settings.environment.account: prod-eu), so upstream would verify it against
# fnx-prod's ID and fail its plan in the right account. account_map must not
# remap fnx-prod (owner), and the mixin has no toggle or account-name input.
#
# How: a stack whose account is not named after its stage gives the account
# name as the null-label descriptor "account_name" (descriptor_formats, the
# null-label input Cloud Posse's account-map names accounts with), templated
# from settings.environment.account. With the descriptor set:
#   - the expected account is the descriptor's value;
#   - verification always runs, fail-closed: a name missing from
#     account_map.full_account_map (or an empty map) fails the precondition
#     instead of skipping it, as does a run in any other account.
# Without it (every other stack), each local is upstream's expression
# unchanged, so their expectation stays "<tenant>-<stage>".
#
# An override file can only replace locals the mixin defines, so the
# descriptor lookup is repeated in each of the three.
#
# Drop this file when upstream takes an account-name input (the E5b5 PR body
# carries the upstream PR text).
locals {
  expected_account_name = lookup(module.this.descriptors, "account_name", null) != null ? module.this.descriptors["account_name"] : (
    try(var.tenant, null) != null &&
    try(var.stage, null) != null &&
    try(var.tenant, "") != "" &&
    try(var.stage, "") != ""
  ) ? "${var.tenant}-${var.stage}" : null

  expected_account_id = lookup(module.this.descriptors, "account_name", null) != null ? lookup(
    var.account_map.full_account_map, module.this.descriptors["account_name"], "<not in account_map>"
    ) : try(
    local.expected_account_name != null ? var.account_map.full_account_map[local.expected_account_name] : null,
    null
  )

  should_validate = lookup(module.this.descriptors, "account_name", null) != null || (
    length(var.account_map.full_account_map) > 0 &&
    local.expected_account_name != null &&
    local.expected_account_id != null
  )
}
