# House override of Cloud Posse's vendored account-map iam-roles module
# (vendor.yaml). The account-map-bypass providers mixin (account_map_enabled
# false) keeps this module with bypass = true: its awsutils_caller_identity data
# source then has count 0, but Terraform still configures this provider, which
# has no region and calls sts:GetCallerIdentity at configure time
# ("sts..amazonaws.com: no such host" when AWS_REGION is unset, as in a local
# run or the plan sweep), and rejects its empty region. Nothing reads AWS
# through it under bypass, so it skips those calls and the region check. Under
# account-map (bypass false) the data source still runs with the caller's
# credentials and region; only the up-front validation is skipped.
provider "awsutils" {
  alias                       = "iam-roles"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}
