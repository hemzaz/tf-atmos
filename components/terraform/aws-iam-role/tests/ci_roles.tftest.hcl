# House tests of the CI roles (stacks/catalog/aws-iam-role/ci.yaml, E6a4) and the Lambda package
# uploader (catalog/aws-iam-role/lambda-uploader.yaml, E6a5, at the end; a vendored target
# admits tests/*.tftest.hcl: scripts/check-vendor.py TESTS) and of
# github-assume-role-policy_override.tf: the exact GitHub OIDC subjects each role trusts
# (master; pull_request on the plan role only where the stage plans pull requests, never in
# prod; an environment constraint kept as it is), no wildcard subject, the trust's audience
# and federated principal, the role names CI derives (ci-apply-role-arn.py), and each role's
# policy (plan: its stage's read-only state role only; apply: the write state role, this
# stack's runner pools and kms/main's alias). Admin and PowerUser on ci-plan, and every
# trusted_github_repos entry's shape, are lint's (check-prod-protection.py), which sees the
# resolved stacks. The real AWS provider with dummy credentials: aws_iam_policy_document
# renders locally, and the one AWS-calling data source is overridden. No AWS.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.account_verification
  values = {
    account_id = "222222222222"
  }
}

# The catalog's values (aws-iam-role/ci, vendored, account-map-bypass) for fnx-ue1-dev's plan role.
variables {
  region      = "us-east-1"
  enabled     = true
  tenant      = "fnx"
  environment = "ue1"
  stage       = "dev"
  name        = "ci-plan"
  # The vendored abstract's context (stacks/catalog/_base/vendored.yaml): its label_order puts
  # tenant in the id, which null-label's default order leaves out.
  context = {
    enabled             = true
    namespace           = null
    tenant              = "fnx"
    environment         = "ue1"
    stage               = "dev"
    name                = null
    delimiter           = null
    attributes          = []
    tags                = {}
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = ["tenant", "environment", "stage", "name", "attributes"]
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags      = ["unset"]
  }

  account_map_enabled = false
  account_map = {
    full_account_map = {
      "fnx-dev"  = "222222222222"
      "fnx-prod" = "444444444444"
    }
  }

  github_oidc_provider_enabled = true
  github_oidc_provider_arn     = "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
  trusted_github_repos         = ["hemzaz/tf-atmos:master", "hemzaz/tf-atmos:pull_request"]
  role_description             = "GitHub Actions OIDC role for terraform plan (read-only)"
  managed_policy_arns          = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  policy_statements = {
    AssumeStateReadRoles = {
      effect    = "Allow"
      actions   = ["sts:AssumeRole"]
      resources = ["arn:aws:iam::111111111111:role/fnx-terraform-backend-read-role"]
    }
  }
}

run "nonprod_plan_role_trusts_master_and_pull_request_exactly" {
  command = plan

  assert {
    condition = toset(flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]])) == toset([
      "repo:hemzaz/tf-atmos:ref:refs/heads/master",
      "repo:hemzaz/tf-atmos:pull_request",
    ])
    error_message = "A nonprod plan role trusts exactly the master ref and pull_request (the override's mapping), never ref:refs/heads/pull_request."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "The trust must require the sts.amazonaws.com audience."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Principal.Federated == "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The trust's only principal is the account's GitHub OIDC provider."
  }

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement) == 1
    error_message = "The GitHub statement must be the trust's only statement (no principals, no assume_role_policy)."
  }

  assert {
    condition     = output.role.name == "fnx-ue1-dev-ci-plan"
    error_message = "The role name is the null-label id <tenant>-<settings.prefix>-<stage>-ci-plan, the ARN ci-apply-role-arn.py derives and the backend trusts."
  }

  assert {
    condition = [for s in jsondecode(output.role.policy).Statement : [s.Sid, flatten([s.Action]), flatten([s.Resource])]] == [
      ["AssumeStateReadRoles", ["sts:AssumeRole"], ["arn:aws:iam::111111111111:role/fnx-terraform-backend-read-role"]],
    ]
    error_message = "The plan role's own policy may only assume its stage's read-only state role."
  }
}

run "prod_plan_role_trusts_master_only" {
  command = plan

  variables {
    stage = "prod"
    # The catalog's prod rendering: the pull_request entry collapses onto master
    # (settings.github.pull_request_plans_enabled false).
    trusted_github_repos     = ["hemzaz/tf-atmos:master", "hemzaz/tf-atmos:master"]
    github_oidc_provider_arn = "arn:aws:iam::444444444444:oidc-provider/token.actions.githubusercontent.com"
  }

  override_data {
    target = data.aws_caller_identity.account_verification
    values = {
      account_id = "444444444444"
    }
  }

  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]]) == ["repo:hemzaz/tf-atmos:ref:refs/heads/master"]
    error_message = "A prod plan role trusts the master ref once and never pull_request (owner decision D3)."
  }

  assert {
    condition     = output.role.name == "fnx-ue1-prod-ci-plan"
    error_message = "The prod plan role keeps its name."
  }
}

run "apply_role_trusts_the_pinned_branch_only" {
  command = plan

  variables {
    name                 = "ci-apply"
    trusted_github_repos = ["hemzaz/tf-atmos:master"]
    managed_policy_arns  = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    policy_statements = {
      AssumeStateWriteRole = {
        effect    = "Allow"
        actions   = ["sts:AssumeRole"]
        resources = ["arn:aws:iam::111111111111:role/fnx-terraform-backend-role"]
      }
      SeeRunnerPools = {
        effect    = "Allow"
        actions   = ["autoscaling:DescribeAutoScalingGroups"]
        resources = ["*"]
      }
      StartRunners = {
        effect    = "Allow"
        actions   = ["autoscaling:ExecutePolicy"]
        resources = ["arn:aws:autoscaling:us-east-1:222222222222:autoScalingGroup:*:autoScalingGroupName/ue1-github-runners"]
      }
    }
    policy_documents = [jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "SyntheticDocument"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::example-bucket/*"]
        },
      ]
    })]
  }

  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]]) == ["repo:hemzaz/tf-atmos:ref:refs/heads/master"]
    error_message = "The apply role trusts only repo:<org>/<repo>:ref:refs/heads/master: no pull_request, environment or wildcard subject."
  }

  assert {
    condition     = output.role.name == "fnx-ue1-dev-ci-apply"
    error_message = "The apply role name is <stack>-ci-apply, the name terraform-cd.yml derives."
  }

  assert {
    condition = toset([for s in jsondecode(output.role.policy).Statement : s.Sid]) == toset([
      "AssumeStateWriteRole", "SeeRunnerPools", "StartRunners", "SyntheticDocument",
    ])
    error_message = "The apply policy merges policy_statements and policy_documents, nothing else."
  }

  assert {
    condition = flatten([for s in jsondecode(output.role.policy).Statement : s.Resource if s.Sid == "StartRunners"]) == [
      "arn:aws:autoscaling:us-east-1:222222222222:autoScalingGroup:*:autoScalingGroupName/ue1-github-runners",
    ]
    error_message = "The apply role may execute the start policy of this stack's own runner pool only."
  }
}

run "environment_and_ref_constraints_pass_through_exactly" {
  command = plan

  variables {
    trusted_github_repos = ["hemzaz/tf-atmos:environment:prod", "hemzaz/tf-atmos:ref:refs/tags/v1.0.0"]
  }

  assert {
    condition = toset(flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]])) == toset([
      "repo:hemzaz/tf-atmos:environment:prod",
      "repo:hemzaz/tf-atmos:ref:refs/tags/v1.0.0",
    ])
    error_message = "The override keeps upstream's environment: and ref: mappings exactly."
  }
}

run "no_wildcard_subject_from_constrained_entries" {
  command = plan

  assert {
    condition = alltrue([
      for sub in flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]]) :
      !strcontains(sub, "*") && !strcontains(sub, "?")
    ])
    error_message = "Constrained entries must render no StringLike wildcard: the match is exact."
  }
}

run "a_constraint_less_entry_keeps_upstreams_wildcard_for_lint_to_fail" {
  command = plan

  variables {
    trusted_github_repos = ["hemzaz/tf-atmos"]
  }

  # The override does not mask upstream's behaviour: lint (check-prod-protection.py) is
  # what rejects such an entry, so this pins the behaviour lint guards against.
  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]]) == ["repo:hemzaz/tf-atmos:*"]
    error_message = "A constraint-less entry renders upstream's repo:<org>/<repo>:* (check-prod-protection.py fails it)."
  }
}

run "another_account_is_refused" {
  command = plan

  variables {
    stage = "prod"
  }

  expect_failures = [terraform_data.account_verification]
}

# The Lambda package uploader (stacks/catalog/aws-iam-role/lambda-uploader.yaml, E6a5) as an
# enabled stack renders it: an application repo's pinned branch. The policy document is synthetic:
# lint proves the catalog's real shape against the describe output.
run "lambda_uploader_trusts_the_app_branch_and_writes_only_its_bucket" {
  command = plan

  variables {
    name                 = "ci-lambda-uploader"
    trusted_github_repos = ["hemzaz/app:main"]
    role_description     = "GitHub Actions OIDC role that uploads Lambda packages to this stage's s3/lambda-artifacts bucket"
    managed_policy_arns  = []
    policy_statements    = {}
    policy_documents = [jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "SyntheticDocument"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::example-bucket/*"]
        },
      ]
    })]
  }

  assert {
    condition     = flatten([jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]]) == ["repo:hemzaz/app:ref:refs/heads/main"]
    error_message = "The uploader trusts only the app repo's pinned branch (upstream's <org>/<repo>:<branch> mapping, kept by the override)."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume_role_policy[0].json).Statement[0].Principal.Federated == "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The uploader trusts the account's GitHub OIDC provider only."
  }

  assert {
    condition     = output.role.name == "fnx-ue1-dev-ci-lambda-uploader"
    error_message = "The uploader keeps the house role's name, <stack>-ci-lambda-uploader."
  }

  assert {
    condition = [for s in jsondecode(output.role.policy).Statement : [s.Sid, flatten([s.Action]), flatten([s.Resource])]] == [
      ["SyntheticDocument", ["s3:GetObject"], ["arn:aws:s3:::example-bucket/*"]],
    ]
    error_message = "The role's policy is the merged policy_documents, nothing else."
  }
}

run "lambda_uploader_off_creates_nothing" {
  command = plan

  variables {
    enabled              = false
    name                 = "ci-lambda-uploader"
    trusted_github_repos = []
    managed_policy_arns  = []
    policy_statements    = {}
  }

  assert {
    condition     = length(data.aws_iam_policy_document.assume_role_policy) == 0
    error_message = "The catalog default (enabled false) creates no trust and no role."
  }
}
