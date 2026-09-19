provider "aws" {
  region = var.region

  dynamic "assume_role" {
    for_each = var.assume_role_arn != null ? [var.assume_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = var.tags
  }
}

# Account hosting public zones when multi_account_dns_delegation is enabled;
# falls back to the default credentials when no role is given
provider "aws" {
  alias  = "dns_account"
  region = var.region

  dynamic "assume_role" {
    for_each = var.dns_account_assume_role_arn != null ? [var.dns_account_assume_role_arn] : []
    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = var.tags
  }
}
