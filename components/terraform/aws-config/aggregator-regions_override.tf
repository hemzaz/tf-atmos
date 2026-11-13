# House override of the vendored Cloud Posse aws-config v3.1.1 main.tf (E5c3b): with
# aggregator_regions set (aggregator-regions_house.tf), the config module's aggregation resources
# (aggregator, authorizations) are off in this region, its own disabled_aggregation_regions input,
# and the house file creates them with named regions. ap-northeast-3 is the module's default.
module "aws_config" {
  #checkov:skip=CKV_TF_1:an override block sets no source; its source is the vendored main.tf registry module, pinned exactly there
  #checkov:skip=CKV_TF_2:an override block sets no source; its source is the vendored main.tf registry module, pinned exactly there
  disabled_aggregation_regions = concat(["ap-northeast-3"], var.aggregator_regions == null ? [] : data.aws_region.this[*].name)
}
