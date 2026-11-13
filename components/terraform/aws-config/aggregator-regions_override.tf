# House override of the vendored Cloud Posse aws-config v3.1.1 main.tf (E5c3b): with
# aggregator_regions or aggregator_authorization_region set (aggregator-regions_house.tf), the
# config module's aggregation resources (its aggregator and both authorizations) are off in this
# region, its own disabled_aggregation_regions input, and the house file replaces them. The
# recorder, delivery channel and rules stay the module's. ap-northeast-3 is the module's default.
module "aws_config" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored main.tf registry module, pinned exactly there
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored main.tf registry module, pinned exactly there
  disabled_aggregation_regions = concat(["ap-northeast-3"],
  var.aggregator_regions == null && var.aggregator_authorization_region == null ? [] : data.aws_region.this[*].name)
}
