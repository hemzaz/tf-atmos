# House override of the vendored Cloud Posse aws-cloudtrail-bucket (vendor.yaml):
# per-residency delivery (owner decisions QE7, E5a OQ4). Cloud Posse's
# cloudtrail-s3-bucket 0.33.0 allows cloudtrail.amazonaws.com and
# config.amazonaws.com to put objects with no aws:SourceAccount or
# aws:SourceArn condition, so any account's trail could write here. Its
# `policy` input is merged in through source_policy_documents, which can only
# add statements (a same-Sid Allow does not replace upstream's), so the
# restriction is two Deny statements:
#   - neither service may put an object for a source account outside this
#     bucket's residency;
#   - CloudTrail may put one only for a trail of such an account
#     (aws:SourceArn, confused-deputy guard).
# The residency is the region's: an eu- bucket (fnx-ew1-audit) takes the
# prod-eu account only, any other (fnx-ue1-audit) every account but prod-eu.
# The accounts come from the static account_map (the account-map-bypass
# abstract), keyed <tenant>-<account>; the preflight
# (check-first-deploy-inputs.py MAP_CONSUMERS) fails an apply with placeholder
# IDs. Inline in the argument: an override file cannot add a local or a
# variable. module.this.id is the bucket name, as upstream's own statements use.
# This replaces the component's `policy` input, so a vars.policy is dropped; the
# preflight fails one (fatal, disabled instances too): add a statement here.
module "cloudtrail_s3_bucket" {
  #checkov:skip=CKV_TF_1:an override block carries no source; Terraform merges it into main.tf's, which pins Cloud Posse's registry module to an exact version
  #checkov:skip=CKV_TF_2:an override block carries no source; Terraform merges it into main.tf's, which pins Cloud Posse's registry module to an exact version
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyDeliveryOutsideResidency"
        Effect    = "Deny"
        Principal = { Service = ["cloudtrail.amazonaws.com", "config.amazonaws.com"] }
        Action    = "s3:PutObject"
        Resource  = "arn:${var.account_map.aws_partition}:s3:::${module.this.id}/*"
        Condition = {
          StringNotEquals = {
            "aws:SourceAccount" = distinct([
              for name, id in var.account_map.full_account_map : id
              if(name == "${module.this.tenant}-prod-eu") == startswith(var.region, "eu-")
            ])
          }
        }
      },
      {
        Sid       = "DenyTrailsOutsideResidency"
        Effect    = "Deny"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:${var.account_map.aws_partition}:s3:::${module.this.id}/*"
        Condition = {
          ArnNotLike = {
            "aws:SourceArn" = distinct([
              for name, id in var.account_map.full_account_map : "arn:${var.account_map.aws_partition}:cloudtrail:*:${id}:trail/*"
              if(name == "${module.this.tenant}-prod-eu") == startswith(var.region, "eu-")
            ])
          }
        }
      },
    ]
  })
}
