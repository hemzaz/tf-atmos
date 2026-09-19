provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# Destination region for cross-region backup copies; falls back to the primary
# region when replication is disabled so the provider can always be configured
provider "aws" {
  alias  = "replica"
  region = coalesce(var.replica_region, var.region)

  default_tags {
    tags = var.tags
  }
}
