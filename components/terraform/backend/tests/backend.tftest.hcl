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

  # Known at plan, so the object ARNs the read roles are scoped to can be
  # matched against real state keys below.
  mock_resource "aws_s3_bucket" {
    override_during = plan
    defaults = {
      arn = "arn:aws:s3:::fnx-terraform-state"
    }
  }
}

# Real state keys, "<workspace_key_prefix = component>/<workspace>/terraform.tfstate",
# where the workspace is the stack name (Atmos appends "-<instance>" for a
# derived instance, e.g. fnx-prod-production-iam-ci), plus their .tflock files.
# The patterns are the ones stacks/catalog/backend/defaults.yaml renders.
variables {
  region      = "us-east-1"
  tenant      = "fnx"
  account_id  = "111111111111"
  bucket_name = "fnx-terraform-state"
  access_roles = {
    read = {
      role_name = "fnx-terraform-backend-read-role"
      allowed_principal_arns = [
        "arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-plan",
        "arn:aws:iam::333333333333:role/fnx-staging-01-staging-ci-plan",
      ]
      write_enabled       = false
      object_key_patterns = ["*/fnx-dev-testenv-01/*", "*/fnx-dev-testenv-01-*", "*/fnx-staging-staging-01/*", "*/fnx-staging-staging-01-*"]
    }
    prod_read = {
      role_name              = "fnx-terraform-backend-prod-read-role"
      write_enabled          = false
      allowed_principal_arns = ["arn:aws:iam::444444444444:role/fnx-production-prod-ci-plan"]
      object_key_patterns    = ["*/fnx-prod-production/*", "*/fnx-prod-production-*"]
    }
    write = {
      role_name = "fnx-terraform-backend-role"
      allowed_principal_arns = [
        "arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-apply",
        "arn:aws:iam::333333333333:role/fnx-staging-01-staging-ci-apply",
      ]
      write_enabled       = true
      object_key_patterns = ["*/fnx-dev-testenv-01/*", "*/fnx-dev-testenv-01-*", "*/fnx-staging-staging-01/*", "*/fnx-staging-staging-01-*"]
    }
    prod_write = {
      role_name              = "fnx-terraform-backend-prod-role"
      write_enabled          = true
      allowed_principal_arns = ["arn:aws:iam::444444444444:role/fnx-production-prod-ci-apply"]
      object_key_patterns    = ["*/fnx-prod-production/*", "*/fnx-prod-production-*"]
    }
    core_write = {
      role_name           = "fnx-terraform-backend-core-role"
      write_enabled       = true
      object_key_patterns = ["*/fnx-core-root/*", "*/fnx-core-root-*"]
    }
  }
}

run "roles_are_named_as_the_stack_backend_expects" {
  command = plan

  assert {
    condition = (
      aws_iam_role.access["write"].name == "fnx-terraform-backend-role"
      && aws_iam_role.access["read"].name == "fnx-terraform-backend-read-role"
      && aws_iam_role.access["prod_write"].name == "fnx-terraform-backend-prod-role"
      && aws_iam_role.access["prod_read"].name == "fnx-terraform-backend-prod-read-role"
      && aws_iam_role.access["core_write"].name == "fnx-terraform-backend-core-role"
    )
    error_message = "The role names are the ones stacks/orgs/fnx/_defaults.yaml's backend template assumes."
  }

  assert {
    condition = (
      output.backend_role_name == "fnx-terraform-backend-role"
      && output.backend_read_role_name == "fnx-terraform-backend-read-role"
      && output.backend_prod_role_name == "fnx-terraform-backend-prod-role"
      && output.backend_prod_read_role_name == "fnx-terraform-backend-prod-read-role"
      && output.backend_core_role_name == "fnx-terraform-backend-core-role"
    )
    error_message = "Every conventional access_roles key has its output (names known at plan; the ARN outputs read the same keys)."
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
      local.access_role_principal_arns["read"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-plan",
        "arn:aws:iam::333333333333:role/fnx-staging-01-staging-ci-plan",
      ])
      && local.access_role_principal_arns["write"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-apply",
        "arn:aws:iam::333333333333:role/fnx-staging-01-staging-ci-apply",
      ])
      && local.access_role_principal_arns["prod_read"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::444444444444:role/fnx-production-prod-ci-plan",
      ])
      && local.access_role_principal_arns["prod_write"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::444444444444:role/fnx-production-prod-ci-apply",
      ])
      && local.access_role_principal_arns["core_write"] == tolist(["arn:aws:iam::111111111111:role/admin"])
    )
    error_message = "Each role trusts exactly its allowed_principal_arns plus the caller (Cloud Posse behaviour): dev/staging CI roles only the non-prod roles, prod's only the prod ones, and the core role the caller alone."
  }

  assert {
    condition = alltrue([
      for key in keys(var.access_roles) :
      one(data.aws_iam_policy_document.access_role_assume[key].statement).condition != null
      && one(one(data.aws_iam_policy_document.access_role_assume[key].statement).condition).test == "ArnEquals"
      && one(one(data.aws_iam_policy_document.access_role_assume[key].statement).condition).variable == "aws:PrincipalArn"
    ])
    error_message = "Account-root principals are only acceptable when narrowed by an ArnEquals aws:PrincipalArn condition."
  }

  assert {
    condition     = local.access_role_principal_accounts["read"] == tolist(["arn:aws:iam::111111111111:root", "arn:aws:iam::222222222222:root", "arn:aws:iam::333333333333:root"]) && local.access_role_principal_accounts["core_write"] == tolist(["arn:aws:iam::111111111111:root"])
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

  variables {
    access_roles = {
      read = {
        role_name              = "fnx-terraform-backend-read-role"
        write_enabled          = false
        allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-plan"]
      }
    }
  }

  assert {
    condition     = local.access_role_principal_arns["read"] == tolist(["arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-plan"])
    error_message = "A root-user caller must never be added to a role's trust."
  }
}

# The core role lists no principals (Cloud Posse's default): with a root-user
# caller it would trust nobody, which the role's precondition refuses.
run "caller_only_role_fails_for_a_root_user_caller" {
  command = plan

  override_data {
    target          = data.aws_iam_session_context.current
    override_during = plan
    values = {
      issuer_arn = "arn:aws:iam::111111111111:root"
    }
  }

  expect_failures = [aws_iam_role.access["core_write"]]
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

# Prefix split (owner decisions): one bucket, but every role reaches only its
# stage's state objects - reads AND writes (non-prod: dev/staging; prod; core).
# The object ARNs each role's GetObject / PutObject statement allows are
# matched against real keys with S3's wildcard semantics ("*" spans "/").
run "non_prod_roles_reach_only_dev_and_staging_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject"], [
        "vpc/fnx-dev-testenv-01/terraform.tfstate",
        "vpc/fnx-dev-testenv-01/terraform.tfstate.tflock",
        "iam/fnx-staging-staging-01-iam-ci/terraform.tfstate",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod read role must read dev and staging state."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "iam/fnx-prod-production/terraform.tfstate",
        "iam/fnx-prod-production-iam-ci/terraform.tfstate",
        "eks/fnx-prod-production-eks-main/terraform.tfstate.tflock",
        ], [
        "backend/fnx-core-root/terraform.tfstate",
        "backend/fnx-core-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod read role (used by PR plans) must not touch any production or fnx-core-root state object."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "vpc/fnx-dev-testenv-01/terraform.tfstate",
        "vpc/fnx-dev-testenv-01/terraform.tfstate.tflock",
        "iam/fnx-staging-staging-01-iam-ci/terraform.tfstate",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod write role must read, write and delete dev and staging state and .tflock objects."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "iam/fnx-prod-production/terraform.tfstate",
        "iam/fnx-prod-production-iam-ci/terraform.tfstate",
        "eks/fnx-prod-production-eks-main/terraform.tfstate.tflock",
        ], [
        "backend/fnx-core-root/terraform.tfstate",
        "backend/fnx-core-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod write role (dev/staging apply roles) must not read, write or delete any production or fnx-core-root object."
  }
}

run "prod_roles_reach_only_prod_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject"], [
        "iam/fnx-prod-production/terraform.tfstate",
        "iam/fnx-prod-production-iam-ci/terraform.tfstate",
        "eks/fnx-prod-production-eks-main/terraform.tfstate.tflock",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod read role must read production state."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "vpc/fnx-dev-testenv-01/terraform.tfstate",
        "vpc/fnx-dev-testenv-01/terraform.tfstate.tflock",
        "iam/fnx-staging-staging-01-iam-ci/terraform.tfstate",
        ], [
        "backend/fnx-core-root/terraform.tfstate",
        "backend/fnx-core-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod read role must not touch non-prod or fnx-core-root state objects."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "iam/fnx-prod-production/terraform.tfstate",
        "iam/fnx-prod-production-iam-ci/terraform.tfstate",
        "eks/fnx-prod-production-eks-main/terraform.tfstate.tflock",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod write role must read, write and delete production state and .tflock objects."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "vpc/fnx-dev-testenv-01/terraform.tfstate",
        "vpc/fnx-dev-testenv-01/terraform.tfstate.tflock",
        "iam/fnx-staging-staging-01-iam-ci/terraform.tfstate",
        ], [
        "backend/fnx-core-root/terraform.tfstate",
        "backend/fnx-core-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod write role must not read, write or delete non-prod or fnx-core-root objects."
  }

  assert {
    condition = length(setintersection(
      toset(flatten([for s in data.aws_iam_policy_document.access_role["prod_read"].statement : tolist(s.actions)])),
      toset(["s3:PutObject", "s3:DeleteObject", "kms:Encrypt", "kms:GenerateDataKey"])
    )) == 0
    error_message = "The prod read role is read-only."
  }
}

run "core_role_reaches_only_core_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "backend/fnx-core-root/terraform.tfstate",
        "backend/fnx-core-root/terraform.tfstate.tflock",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["core_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The core role must read, write and delete the backend's own (fnx-core-root) state."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "vpc/fnx-dev-testenv-01/terraform.tfstate",
        "vpc/fnx-dev-testenv-01/terraform.tfstate.tflock",
        "iam/fnx-staging-staging-01-iam-ci/terraform.tfstate",
        ], [
        "iam/fnx-prod-production/terraform.tfstate",
        "iam/fnx-prod-production-iam-ci/terraform.tfstate",
        "eks/fnx-prod-production-eks-main/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["core_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The core role must not touch workload state."
  }
}

# Each stack's pair is exact: a stack whose name merely extends a listed one
# (fnx-dev-testenv-010) is not that stack, so no role reaches it until its own
# pair is added. The old "*/<tenant>-<stage>-*" patterns reached any such name.
run "exact_pairs_do_not_reach_a_stack_extending_a_listed_name" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(keys(var.access_roles), [
        "vpc/fnx-dev-testenv-010/terraform.tfstate",
        "vpc/fnx-staging-staging-01x/terraform.tfstate.tflock",
        "vpc/fnx-prod-productionx/terraform.tfstate",
        "backend/fnx-core-rootx/terraform.tfstate",
        ]) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role[pair[0]].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), "s3:GetObject")
      ])
    ])
    error_message = "No role may reach a stack that is not in its object_key_patterns."
  }
}

run "read_roles_get_the_disaster_recovery_listing_and_write_roles_do_not" {
  command = plan

  assert {
    condition = alltrue([
      for key in ["read", "prod_read"] : length(setintersection(
        toset(flatten([for s in data.aws_iam_policy_document.access_role[key].statement : tolist(s.actions)])),
        toset(["s3:ListBucketVersions", "s3:GetBucketVersioning", "s3:GetReplicationConfiguration"])
      )) == 3
    ])
    error_message = "The DR checks (workflows/scripts/dr) list state versions and read the bucket's versioning/replication through the read roles."
  }

  assert {
    condition = alltrue([
      for key in ["read", "prod_read", "write", "prod_write", "core_write"] : !contains(
        flatten([for s in data.aws_iam_policy_document.access_role[key].statement : tolist(s.actions)]), "s3:GetObjectVersion"
      )
    ])
    error_message = "No role may read an old object version: ListBucketVersions shows names and version IDs only."
  }

  assert {
    condition = alltrue([
      for key in ["write", "prod_write", "core_write"] : !contains(
        flatten([for s in data.aws_iam_policy_document.access_role[key].statement : tolist(s.actions)]), "s3:ListBucketVersions"
      )
    ])
    error_message = "Only the read-only roles carry the DR listing statement."
  }
}

run "rejects_empty_object_key_patterns" {
  command = plan

  variables {
    access_roles = {
      read = {
        role_name              = "fnx-terraform-backend-read-role"
        write_enabled          = false
        allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-testenv-01-dev-ci-plan"]
        object_key_patterns    = []
      }
    }
  }

  expect_failures = [var.access_roles]
}
