provider "aws" {
  alias  = "default"
  region = var.aws_region
  version = "~> 5.0"
  assume_role {
    role_arn = "arn:aws:iam::${var.shared_account_id}:role/SharedServicesAccessRole"
  }
}

provider "aws" {
  alias  = "target_account"
  region = var.aws_region
  version = "~> 5.0"
  assume_role {
    role_arn = "arn:aws:iam::${var.env_account_id}:role/EnvironmentAccessRole"
  }
}
