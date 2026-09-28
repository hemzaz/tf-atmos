# Mock-provider tests for the state access roles (iam.tf): no AWS credentials.
# Run from the component directory: terraform init -backend=false && terraform test
#
# Plan only: the state buckets carry prevent_destroy, so an applied run could
# not be cleaned up. The assertions read the policy documents' statement blocks
# (configuration, known at plan) rather than their rendered JSON.

mock_provider "aws" {
  override_data {
    target          = data.aws_caller_identity.current
    override_during = plan
    values = {
      account_id = "111111111111"
      arn        = "arn:aws:sts::111111111111:assumed-role/admin/operator"
    }
  }

  override_data {
    target          = data.aws_iam_session_context.current
    override_during = plan
    values = {
      issuer_arn = "arn:aws:iam::111111111111:role/admin"
    }
  }

  # A mocked data source returns a random string for `json`, which the IAM
  # resources reject as a policy. The statements asserted on below are the
  # configured blocks, not this rendered document.
  override_data {
    target          = data.aws_iam_policy_document.access_role_assume
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.access_role
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.bucket
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  region      = "eu-west-2"
  tenant      = "fnx"
  account_id  = "111111111111"
  bucket_name = "fnx-terraform-state"
  access_roles = {
    read = {
      role_name              = "fnx-terraform-backend-read-role"
      write_enabled          = false
      allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-plan"]
    }
    write = {
      role_name              = "fnx-terraform-backend-role"
      write_enabled          = true
      allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-apply"]
    }
  }
}

run "roles_are_named_as_the_stack_backend_expects" {
  command = plan

  assert {
    condition     = aws_iam_role.access["write"].name == "fnx-terraform-backend-role" && aws_iam_role.access["read"].name == "fnx-terraform-backend-read-role"
    error_message = "The write role keeps the name stacks/orgs/fnx/_defaults.yaml assumes; the read role gets its own name."
  }
}

run "read_role_cannot_write_state_or_encrypt" {
  command = plan

  assert {
    condition = length(setintersection(
      toset(flatten([for s in data.aws_iam_policy_document.access_role["read"].statement : tolist(s.actions)])),
      toset(["s3:PutObject", "s3:DeleteObject", "kms:Encrypt", "kms:GenerateDataKey"])
    )) == 0
    error_message = "The read role must not be able to write or delete state/lock objects or encrypt with the state key."
  }

  assert {
    condition = length(setintersection(
      toset(flatten([for s in data.aws_iam_policy_document.access_role["read"].statement : tolist(s.actions)])),
      toset(["s3:ListBucket", "s3:GetObject", "kms:Decrypt"])
    )) == 3
    error_message = "The read role must be able to list the bucket, read state and decrypt it."
  }
}

run "write_role_can_write_state_and_lock_files" {
  command = plan

  assert {
    condition = length(setintersection(
      toset(flatten([for s in data.aws_iam_policy_document.access_role["write"].statement : tolist(s.actions)])),
      toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"])
    )) == 6
    error_message = "The write role must be able to read, write and delete state and .tflock objects, and use the key for both."
  }
}

run "trust_is_limited_to_named_principals_and_the_caller" {
  command = plan

  assert {
    condition = (
      local.access_role_principal_arns["read"] == tolist(["arn:aws:iam::111111111111:role/admin", "arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-plan"])
      && local.access_role_principal_arns["write"] == tolist(["arn:aws:iam::111111111111:role/admin", "arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-apply"])
    )
    error_message = "Each role trusts its allowed_principal_arns plus the caller (Cloud Posse behaviour), nothing else."
  }

  assert {
    condition = alltrue([
      for key in ["read", "write"] :
      one(data.aws_iam_policy_document.access_role_assume[key].statement).condition != null
      && one(one(data.aws_iam_policy_document.access_role_assume[key].statement).condition).test == "ArnEquals"
      && one(one(data.aws_iam_policy_document.access_role_assume[key].statement).condition).variable == "aws:PrincipalArn"
    ])
    error_message = "Account-root principals are only acceptable when narrowed by an ArnEquals aws:PrincipalArn condition."
  }

  assert {
    condition     = local.access_role_principal_accounts["read"] == tolist(["arn:aws:iam::111111111111:root", "arn:aws:iam::222222222222:root"])
    error_message = "The trust policy's principals are the accounts of the allowed ARNs."
  }
}

run "root_user_caller_is_not_trusted" {
  command = plan

  override_data {
    target          = data.aws_iam_session_context.current
    override_during = plan
    values = {
      issuer_arn = "arn:aws:iam::111111111111:root"
    }
  }

  assert {
    condition     = local.access_role_principal_arns["read"] == tolist(["arn:aws:iam::222222222222:role/fnx-dev-testenv-01-ci-plan"])
    error_message = "A root-user caller must never be added to a role's trust."
  }
}

run "rejects_wildcard_principal" {
  command = plan

  variables {
    access_roles = {
      read = {
        role_name              = "fnx-terraform-backend-read-role"
        write_enabled          = false
        allowed_principal_arns = ["*"]
      }
    }
  }

  expect_failures = [var.access_roles]
}

run "rejects_wildcard_inside_an_arn" {
  command = plan

  variables {
    access_roles = {
      read = {
        role_name              = "fnx-terraform-backend-read-role"
        write_enabled          = false
        allowed_principal_arns = ["arn:aws:iam::222222222222:role/*"]
      }
    }
  }

  expect_failures = [var.access_roles]
}

run "rejects_account_root_principal" {
  command = plan

  variables {
    access_roles = {
      write = {
        role_name              = "fnx-terraform-backend-role"
        write_enabled          = true
        allowed_principal_arns = ["arn:aws:iam::222222222222:root"]
      }
    }
  }

  expect_failures = [var.access_roles]
}

run "rejects_empty_principal_list" {
  command = plan

  variables {
    access_roles = {
      write = {
        role_name              = "fnx-terraform-backend-role"
        write_enabled          = true
        allowed_principal_arns = []
      }
    }
  }

  expect_failures = [var.access_roles]
}
