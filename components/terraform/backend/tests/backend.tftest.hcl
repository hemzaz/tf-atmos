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

  override_data {
    target          = data.aws_iam_policy_document.terraform_state_replica
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.replication_assume
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.terraform_state_replica_writes
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.replication
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
# derived instance, e.g. fnx-ue1-prod-iam-ci), plus their .tflock files.
# The patterns are the ones backend/main renders in stacks/orgs/fnx/root/us-east-1.yaml.
variables {
  region      = "us-east-1"
  account_id  = "111111111111"
  bucket_name = "fnx-terraform-state"
  access_roles = {
    read = {
      role_name = "fnx-terraform-backend-read-role"
      allowed_principal_arns = [
        "arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-plan",
        "arn:aws:iam::333333333333:role/fnx-ue1-staging-ci-plan",
      ]
      write_enabled       = false
      object_key_patterns = ["*/fnx-ue1-dev/*", "*/fnx-ue1-dev-*", "*/fnx-ue1-staging/*", "*/fnx-ue1-staging-*"]
    }
    prod_read = {
      role_name              = "fnx-terraform-backend-prod-read-role"
      write_enabled          = false
      allowed_principal_arns = ["arn:aws:iam::444444444444:role/fnx-ue1-prod-ci-plan"]
      object_key_patterns    = ["*/fnx-ue1-prod/*", "*/fnx-ue1-prod-*"]
    }
    write = {
      role_name = "fnx-terraform-backend-role"
      allowed_principal_arns = [
        "arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-apply",
        "arn:aws:iam::333333333333:role/fnx-ue1-staging-ci-apply",
      ]
      write_enabled       = true
      object_key_patterns = ["*/fnx-ue1-dev/*", "*/fnx-ue1-dev-*", "*/fnx-ue1-staging/*", "*/fnx-ue1-staging-*"]
    }
    prod_write = {
      role_name              = "fnx-terraform-backend-prod-role"
      write_enabled          = true
      allowed_principal_arns = ["arn:aws:iam::444444444444:role/fnx-ue1-prod-ci-apply"]
      object_key_patterns    = ["*/fnx-ue1-prod/*", "*/fnx-ue1-prod-*"]
    }
    root_write = {
      role_name           = "fnx-terraform-backend-root-role"
      write_enabled       = true
      object_key_patterns = ["*/fnx-ue1-root/*", "*/fnx-ue1-root-*"]
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
      && aws_iam_role.access["root_write"].name == "fnx-terraform-backend-root-role"
    )
    error_message = "The role names are the ones stacks/orgs/fnx/_defaults.yaml's backend template assumes."
  }

  assert {
    condition = (
      output.backend_role_name == "fnx-terraform-backend-role"
      && output.backend_read_role_name == "fnx-terraform-backend-read-role"
      && output.backend_prod_role_name == "fnx-terraform-backend-prod-role"
      && output.backend_prod_read_role_name == "fnx-terraform-backend-prod-read-role"
      && output.backend_root_role_name == "fnx-terraform-backend-root-role"
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
        "arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-plan",
        "arn:aws:iam::333333333333:role/fnx-ue1-staging-ci-plan",
      ])
      && local.access_role_principal_arns["write"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-apply",
        "arn:aws:iam::333333333333:role/fnx-ue1-staging-ci-apply",
      ])
      && local.access_role_principal_arns["prod_read"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::444444444444:role/fnx-ue1-prod-ci-plan",
      ])
      && local.access_role_principal_arns["prod_write"] == tolist([
        "arn:aws:iam::111111111111:role/admin",
        "arn:aws:iam::444444444444:role/fnx-ue1-prod-ci-apply",
      ])
      && local.access_role_principal_arns["root_write"] == tolist(["arn:aws:iam::111111111111:role/admin"])
    )
    error_message = "Each role trusts exactly its allowed_principal_arns plus the caller (Cloud Posse behaviour): dev/staging CI roles only the non-prod roles, prod's only the prod ones, and the root role the caller alone."
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
    condition     = local.access_role_principal_accounts["read"] == tolist(["arn:aws:iam::111111111111:root", "arn:aws:iam::222222222222:root", "arn:aws:iam::333333333333:root"]) && local.access_role_principal_accounts["root_write"] == tolist(["arn:aws:iam::111111111111:root"])
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
        allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-plan"]
      }
    }
  }

  assert {
    condition     = local.access_role_principal_arns["read"] == tolist(["arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-plan"])
    error_message = "A root-user caller must never be added to a role's trust."
  }
}

# The root role lists no principals (Cloud Posse's default): with a root-user
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

  expect_failures = [aws_iam_role.access["root_write"]]
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
# stage's state objects - reads AND writes (non-prod: dev/staging; prod; root).
# The object ARNs each role's GetObject / PutObject statement allows are
# matched against real keys with S3's wildcard semantics ("*" spans "/").
run "non_prod_roles_reach_only_dev_and_staging_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject"], [
        "vpc/fnx-ue1-dev/terraform.tfstate",
        "vpc/fnx-ue1-dev/terraform.tfstate.tflock",
        "iam/fnx-ue1-staging-iam-ci/terraform.tfstate",
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
        "iam/fnx-ue1-prod/terraform.tfstate",
        "iam/fnx-ue1-prod-iam-ci/terraform.tfstate",
        "eks/fnx-ue1-prod-eks-main/terraform.tfstate.tflock",
        ], [
        "backend/fnx-ue1-root/terraform.tfstate",
        "backend/fnx-ue1-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod read role (used by PR plans) must not touch any production or fnx-ue1-root state object."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "vpc/fnx-ue1-dev/terraform.tfstate",
        "vpc/fnx-ue1-dev/terraform.tfstate.tflock",
        "iam/fnx-ue1-staging-iam-ci/terraform.tfstate",
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
        "iam/fnx-ue1-prod/terraform.tfstate",
        "iam/fnx-ue1-prod-iam-ci/terraform.tfstate",
        "eks/fnx-ue1-prod-eks-main/terraform.tfstate.tflock",
        ], [
        "backend/fnx-ue1-root/terraform.tfstate",
        "backend/fnx-ue1-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The non-prod write role (dev/staging apply roles) must not read, write or delete any production or fnx-ue1-root object."
  }
}

run "prod_roles_reach_only_prod_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject"], [
        "iam/fnx-ue1-prod/terraform.tfstate",
        "iam/fnx-ue1-prod-iam-ci/terraform.tfstate",
        "eks/fnx-ue1-prod-eks-main/terraform.tfstate.tflock",
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
        "vpc/fnx-ue1-dev/terraform.tfstate",
        "vpc/fnx-ue1-dev/terraform.tfstate.tflock",
        "iam/fnx-ue1-staging-iam-ci/terraform.tfstate",
        ], [
        "backend/fnx-ue1-root/terraform.tfstate",
        "backend/fnx-ue1-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_read"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod read role must not touch non-prod or fnx-ue1-root state objects."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "iam/fnx-ue1-prod/terraform.tfstate",
        "iam/fnx-ue1-prod-iam-ci/terraform.tfstate",
        "eks/fnx-ue1-prod-eks-main/terraform.tfstate.tflock",
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
        "vpc/fnx-ue1-dev/terraform.tfstate",
        "vpc/fnx-ue1-dev/terraform.tfstate.tflock",
        "iam/fnx-ue1-staging-iam-ci/terraform.tfstate",
        ], [
        "backend/fnx-ue1-root/terraform.tfstate",
        "backend/fnx-ue1-root/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["prod_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The prod write role must not read, write or delete non-prod or fnx-ue1-root objects."
  }

  assert {
    condition = length(setintersection(
      toset(flatten([for s in data.aws_iam_policy_document.access_role["prod_read"].statement : tolist(s.actions)])),
      toset(["s3:PutObject", "s3:DeleteObject", "kms:Encrypt", "kms:GenerateDataKey"])
    )) == 0
    error_message = "The prod read role is read-only."
  }
}

run "root_role_reaches_only_root_objects" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], [
        "backend/fnx-ue1-root/terraform.tfstate",
        "backend/fnx-ue1-root/terraform.tfstate.tflock",
        ]) : anytrue([
        for statement in data.aws_iam_policy_document.access_role["root_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The root role must read, write and delete the backend's own (fnx-ue1-root) state."
  }

  assert {
    condition = alltrue([
      for pair in setproduct(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], concat([
        "vpc/fnx-ue1-dev/terraform.tfstate",
        "vpc/fnx-ue1-dev/terraform.tfstate.tflock",
        "iam/fnx-ue1-staging-iam-ci/terraform.tfstate",
        ], [
        "iam/fnx-ue1-prod/terraform.tfstate",
        "iam/fnx-ue1-prod-iam-ci/terraform.tfstate",
        "eks/fnx-ue1-prod-eks-main/terraform.tfstate.tflock",
        ])) : !anytrue([
        for statement in data.aws_iam_policy_document.access_role["root_write"].statement : anytrue([
          for arn in tolist(statement.resources) :
          can(regex("^${replace(replace(arn, ".", "\\."), "*", ".*")}$", "arn:aws:s3:::fnx-terraform-state/${pair[1]}"))
        ]) if contains(tolist(statement.actions), pair[0])
      ])
    ])
    error_message = "The root role must not touch workload state."
  }
}

# Each stack's pair is exact: a stack whose name merely extends a listed one
# (fnx-ue1-dev0) is not that stack, so no role reaches it until its own
# pair is added. The old "*/<tenant>-<stage>-*" patterns reached any such name.
run "exact_pairs_do_not_reach_a_stack_extending_a_listed_name" {
  command = plan

  assert {
    condition = alltrue([
      for pair in setproduct(keys(var.access_roles), [
        "vpc/fnx-ue1-dev0/terraform.tfstate",
        "vpc/fnx-ue1-stagingx/terraform.tfstate.tflock",
        "vpc/fnx-ue1-prodx/terraform.tfstate",
        "backend/fnx-ue1-rootx/terraform.tfstate",
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
      for key in ["read", "prod_read", "write", "prod_write", "root_write"] : !contains(
        flatten([for s in data.aws_iam_policy_document.access_role[key].statement : tolist(s.actions)]), "s3:GetObjectVersion"
      )
    ])
    error_message = "No role may read an old object version: ListBucketVersions shows names and version IDs only."
  }

  assert {
    condition = alltrue([
      for key in ["write", "prod_write", "root_write"] : !contains(
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
        allowed_principal_arns = ["arn:aws:iam::222222222222:role/fnx-ue1-dev-ci-plan"]
        object_key_patterns    = []
      }
    }
  }

  expect_failures = [var.access_roles]
}

# --- Cross-region replication of the state bucket (replication.tf) ---

run "replication_is_off_by_default" {
  command = plan

  assert {
    condition = (
      length(aws_s3_bucket.terraform_state_replica) == 0
      && length(aws_s3_bucket_replication_configuration.terraform_state) == 0
      && length(aws_iam_role.replication) == 0
      && !contains(flatten([for s in data.aws_iam_policy_document.access_role["read"].statement : [s.sid]]), "ReadStateReplica")
    )
    error_message = "Without s3_replication_enabled there is no replica, no replication and no replica grant."
  }

  assert {
    condition     = aws_kms_key.terraform_state_key.multi_region == true
    error_message = "The state key is always multi-region: turning that on later would replace the key the state is encrypted with."
  }
}

run "replication_creates_the_replica_in_the_replica_region" {
  command = plan

  variables {
    s3_replication_enabled = true
    replica_region         = "us-east-2"
  }

  assert {
    condition = (
      aws_s3_bucket.terraform_state_replica[0].bucket == "fnx-terraform-state-replica"
      && aws_s3_bucket.terraform_state_replica[0].region == "us-east-2"
      && aws_kms_replica_key.terraform_state[0].region == "us-east-2"
      && aws_s3_bucket_versioning.terraform_state_replica[0].versioning_configuration[0].status == "Enabled"
    )
    error_message = "The replica bucket and its key must be in replica_region, versioned."
  }

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.terraform_state_replica[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
      && aws_s3_bucket_public_access_block.terraform_state_replica[0].restrict_public_buckets == true
    )
    error_message = "The replica must be SSE-KMS and private, as the source."
  }

  assert {
    condition = (
      aws_s3_bucket_replication_configuration.terraform_state[0].rule[0].status == "Enabled"
      && aws_s3_bucket_replication_configuration.terraform_state[0].rule[0].delete_marker_replication[0].status == "Enabled"
      && aws_s3_bucket_replication_configuration.terraform_state[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Enabled"
    )
    error_message = "Every SSE-KMS state and lock object must replicate, deletes included."
  }

  assert {
    condition     = aws_iam_role.replication[0].name == "fnx-terraform-state-replication"
    error_message = "The replication role is named after the bucket."
  }
}

run "replication_role_is_least_privilege" {
  command = plan

  variables {
    s3_replication_enabled = true
    replica_region         = "us-east-2"
  }

  assert {
    condition = toset(flatten([for s in data.aws_iam_policy_document.replication[0].statement : tolist(s.actions)])) == toset([
      "s3:GetReplicationConfiguration", "s3:ListBucket",
      "s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging",
      "s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags",
      "kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey",
    ])
    error_message = "The replication role gets the replication actions only, as Cloud Posse's tfstate-backend."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.replication[0].statement :
      contains([for c in s.condition : c.variable], "kms:ViaService")
      if anytrue([for a in s.actions : startswith(a, "kms:")])
    ])
    error_message = "Key use must be limited to S3 (kms:ViaService)."
  }
}

run "every_role_reads_the_replica_and_none_writes_it" {
  command = plan

  variables {
    s3_replication_enabled = true
    replica_region         = "us-east-2"
  }

  assert {
    condition = alltrue([
      for key in ["read", "prod_read", "write", "prod_write", "root_write"] : alltrue([
        for s in data.aws_iam_policy_document.access_role[key].statement :
        toset(s.actions) == toset(["s3:GetObject"])
        if s.sid == "ReadStateReplica"
      ]) && contains([for s in data.aws_iam_policy_document.access_role[key].statement : s.sid], "ReadStateReplica")
    ])
    error_message = "Every role, write roles included, may only GetObject in the replica."
  }

  assert {
    condition = alltrue([
      for key in ["write", "prod_write"] : alltrue([
        for s in data.aws_iam_policy_document.access_role[key].statement :
        toset(s.actions) == toset(["kms:Decrypt", "kms:DescribeKey"])
        if s.sid == "UseStateReplicaKey"
      ]) && contains([for s in data.aws_iam_policy_document.access_role[key].statement : s.sid], "UseStateReplicaKey")
    ])
    error_message = "The replica key is for decrypting only: a run against the replica cannot write."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.access_role["prod_read"].statement :
      toset(s.resources) == toset(["arn:aws:s3:::fnx-terraform-state/*/fnx-ue1-prod/*", "arn:aws:s3:::fnx-terraform-state/*/fnx-ue1-prod-*"])
      if s.sid == "ReadStateReplica"
    ])
    error_message = "Replica reads keep each role's object_key_patterns (the mock gives every bucket the same ARN)."
  }
}

run "replication_without_a_region_is_rejected" {
  command = plan

  variables {
    s3_replication_enabled = true
  }

  expect_failures = [var.replica_region]
}

run "replica_in_the_bucket_region_is_rejected" {
  command = plan

  variables {
    s3_replication_enabled = true
    replica_region         = "us-east-1"
  }

  expect_failures = [var.replica_region]
}

run "replica_bucket_policy_denies_writes_to_all_but_replication" {
  command = plan

  variables {
    s3_replication_enabled = true
    replica_region         = "us-east-2"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.terraform_state_replica_writes[0].statement :
      s.effect == "Deny"
      && length(setintersection(toset(s.actions), toset(["s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutObjectTagging"]))) == 4
      && anytrue([for c in s.condition : c.test == "StringNotEquals" && c.variable == "aws:PrincipalArn"])
      && anytrue([for p in s.principals : contains(tolist(p.identifiers), "*")])
    ])
    error_message = "The replica's bucket policy must deny object writes, tags and deletes to every principal but the replication role."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.terraform_state_replica_writes[0].source_policy_documents) == 1
    error_message = "The write deny is added to the TLS-only policy, not instead of it."
  }
}
